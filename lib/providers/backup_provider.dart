import 'package:flutter/foundation.dart';

import '../db/db_helper.dart';
import '../services/google_auth_service.dart';
import '../services/sheets_backup_service.dart';

/// Estado de la cuenta de Google y del respaldo en Sheets.
///
/// Todo acá es opcional por diseño: si nunca se conecta una cuenta, o si
/// Google falla, la app sigue funcionando igual contra SQLite. Este
/// provider nunca bloquea el registro de movimientos.
class BackupProvider extends ChangeNotifier {
  BackupProvider({
    GoogleAuthService? auth,
    SheetsBackupService? sheets,
    DBHelper? db,
  })  : _auth = auth ?? GoogleAuthService(),
        _sheets = sheets ?? SheetsBackupService(),
        _db = db ?? DBHelper.instance;

  final GoogleAuthService _auth;
  final SheetsBackupService _sheets;
  final DBHelper _db;

  String? _accountEmail;
  DateTime? _lastBackup;
  DateTime? _dataChangedAt;
  bool _busy = false;
  String? _errorMessage;
  String? _errorDetail;

  String? get accountEmail => _accountEmail;
  bool get isConnected => _accountEmail != null;
  DateTime? get lastBackup => _lastBackup;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  String? get errorDetail => _errorDetail;

  /// Queda en true cuando falta el client ID de Google en la config
  /// nativa. Es un error de configuración del proyecto, no del usuario.
  bool get isMissingConfiguration => _auth.isMissingConfiguration;

  /// Hay movimientos o categorías escritos después del último respaldo.
  bool get hasPendingChanges {
    final changed = _dataChangedAt;
    if (changed == null) return false;
    final backup = _lastBackup;
    return backup == null || changed.isAfter(backup);
  }

  /// Recupera la sesión anterior sin mostrar nada y, si hay cambios sin
  /// subir, los sube en silencio.
  Future<void> init() async {
    await _loadStoredState();
    notifyListeners();

    final account = await _auth.initializeAndRestore();
    if (account == null) {
      // La sesión pudo haber caducado: el mail guardado en SQLite ya no
      // representa una cuenta usable, así que no se muestra conectada.
      _accountEmail = null;
      notifyListeners();
      return;
    }

    _accountEmail = account.email;
    await _db.setSetting(DBHelper.settingGoogleAccount, account.email);
    notifyListeners();

    await backupIfPending();
  }

  Future<void> _loadStoredState() async {
    _accountEmail = await _db.getSetting(DBHelper.settingGoogleAccount);
    _lastBackup = await _db.getSettingAsDate(DBHelper.settingLastBackup);
    _dataChangedAt = await _db.getSettingAsDate(DBHelper.settingDataChangedAt);
  }

  /// Login explícito desde Ajustes. Devuelve el resultado para que la
  /// pantalla decida qué mensaje mostrar (cancelar no es un error).
  Future<GoogleAuthResult> connect() async {
    _startWork();
    try {
      final result = await _auth.connect();
      if (result.isConnected) {
        final email = result.account!.email;
        _accountEmail = email;
        await _db.setSetting(DBHelper.settingGoogleAccount, email);
      } else if (result.outcome != GoogleAuthOutcome.canceled) {
        _errorMessage = 'No se pudo conectar la cuenta.';
        _errorDetail = result.detail;
      }
      return result;
    } finally {
      _finishWork();
    }
  }

  Future<void> disconnect() async {
    _startWork();
    try {
      await _auth.disconnect();
      _accountEmail = null;
      await _db.deleteSetting(DBHelper.settingGoogleAccount);
      // El id de la planilla se olvida también: al reconectar se
      // reencuentra por su etiqueta en Drive. La planilla **no** se
      // borra: desconectar la cuenta no es tirar el respaldo.
      await _db.deleteSetting(DBHelper.settingSpreadsheetId);
    } finally {
      _finishWork();
    }
  }

  /// Sube un respaldo. Con [interactive] en true puede pedirle permisos
  /// al usuario; en false falla en silencio y deja el respaldo pendiente.
  Future<bool> backupNow({bool interactive = true}) async {
    if (!isConnected || _busy) return false;

    _startWork();
    try {
      final token = await _auth.accessToken(interactive: interactive);
      if (token == null) {
        if (interactive) {
          _errorMessage = 'Google no dio permiso para escribir el respaldo.';
        }
        return false;
      }

      final cachedId = await _db.getSetting(DBHelper.settingSpreadsheetId);
      final spreadsheetId =
          await _sheets.ensureSpreadsheet(token, cachedId: cachedId);
      if (spreadsheetId != cachedId) {
        await _db.setSetting(DBHelper.settingSpreadsheetId, spreadsheetId);
      }

      await _sheets.upload(
        token: token,
        spreadsheetId: spreadsheetId,
        categories: await _db.getCategories(),
        transactions: await _db.getTransactions(),
      );

      final now = DateTime.now();
      await _db.setSetting(DBHelper.settingLastBackup, now.toIso8601String());
      _lastBackup = now;
      return true;
    } on SheetsBackupException catch (e) {
      _errorMessage = e.message;
      _errorDetail = e.detail;
      return false;
    } finally {
      _finishWork();
    }
  }

  /// Respaldo automático: corre al mandar la app a segundo plano y al
  /// arrancar, solo si hay algo nuevo y sin molestar con diálogos.
  Future<void> backupIfPending() async {
    if (!isConnected) return;
    // Se relee de SQLite y no se confía en lo que haya en memoria: los
    // movimientos se cargan en otra pestaña, que no le avisa a este
    // provider. Con el valor viejo, el respaldo al salir de la app se
    // salteaba justo los movimientos recién cargados.
    _dataChangedAt = await _db.getSettingAsDate(DBHelper.settingDataChangedAt);
    if (!hasPendingChanges) return;
    await backupNow(interactive: false);
  }

  /// Trae el respaldo y **reemplaza** los datos locales.
  ///
  /// Es la única operación destructiva de todo esto, así que no se llama
  /// sola nunca: la pantalla pide confirmación antes. Devuelve false si
  /// no se pudo, dejando la base local intacta.
  Future<bool> restoreFromBackup() async {
    if (!isConnected || _busy) return false;

    _startWork();
    try {
      final token = await _auth.accessToken(interactive: true);
      if (token == null) {
        _errorMessage = 'Google no dio permiso para leer el respaldo.';
        return false;
      }

      final cachedId = await _db.getSetting(DBHelper.settingSpreadsheetId);
      final spreadsheetId =
          await _sheets.ensureSpreadsheet(token, cachedId: cachedId);
      await _db.setSetting(DBHelper.settingSpreadsheetId, spreadsheetId);

      final snapshot = await _sheets.download(
        token: token,
        spreadsheetId: spreadsheetId,
      );
      if (snapshot.isEmpty) {
        _errorMessage = 'El respaldo está vacío: no se tocó nada.';
        return false;
      }

      await _db.replaceAllData(
        categories: snapshot.categories,
        transactions: snapshot.transactions,
      );
      await _loadStoredState();
      return true;
    } on SheetsBackupException catch (e) {
      _errorMessage = e.message;
      _errorDetail = e.detail;
      return false;
    } finally {
      _finishWork();
    }
  }

  /// Relee de SQLite cuándo fue la última escritura. Lo llama la pantalla
  /// de Ajustes al abrirse, para que "cambios sin respaldar" no quede
  /// viejo después de cargar movimientos en otra pestaña.
  Future<void> refresh() async {
    _dataChangedAt = await _db.getSettingAsDate(DBHelper.settingDataChangedAt);
    _lastBackup = await _db.getSettingAsDate(DBHelper.settingLastBackup);
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null && _errorDetail == null) return;
    _errorMessage = null;
    _errorDetail = null;
    notifyListeners();
  }

  void _startWork() {
    _busy = true;
    _errorMessage = null;
    _errorDetail = null;
    notifyListeners();
  }

  void _finishWork() {
    _busy = false;
    notifyListeners();
  }
}
