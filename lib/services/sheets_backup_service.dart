import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/category_model.dart';
import '../models/transaction_model.dart';

/// Falla esperable del respaldo (sin red, token vencido, planilla
/// editada a mano y ya ilegible). Lleva un mensaje listo para mostrar.
class SheetsBackupException implements Exception {
  SheetsBackupException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Lo que hay guardado en la planilla, ya parseado.
class BackupSnapshot {
  const BackupSnapshot({required this.categories, required this.transactions});

  final List<CategoryModel> categories;
  final List<TransactionModel> transactions;

  bool get isEmpty => categories.isEmpty && transactions.isEmpty;
}

/// Respaldo de los datos de Nexo en una hoja de cálculo de Google.
///
/// Habla con las APIs REST de Sheets y Drive directamente, con el token
/// que da `GoogleAuthService`. El scope es `drive.file`, así que todo
/// esto solo alcanza a la planilla que la app misma creó.
class SheetsBackupService {
  SheetsBackupService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _driveFiles = 'https://www.googleapis.com/drive/v3/files';
  static const String _sheetsApi =
      'https://sheets.googleapis.com/v4/spreadsheets';

  /// Etiqueta privada de la app sobre el archivo de Drive. Es lo que
  /// permite reencontrar la planilla después de reinstalar la app, cuando
  /// el id guardado en SQLite ya no está.
  static const String _tagKey = 'nexoRespaldo';
  static const String _tagValue = 'v1';

  static const String spreadsheetTitle = 'Nexo — Respaldo';

  static const String _sheetTransactions = 'movimientos';
  static const String _sheetCategories = 'categorias';
  static const String _sheetInfo = 'info';

  static const List<String> _categoryHeader = [
    'id',
    'nombre',
    'icono',
    'por_defecto',
  ];
  static const List<String> _transactionHeader = [
    'id',
    'fecha',
    'tipo',
    'monto',
    'categoria_id',
    'categoria',
    'icono',
    'nota',
  ];

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Devuelve el id de la planilla de respaldo, creándola si hace falta.
  ///
  /// [cachedId] es el id que la app tenía anotado. Se verifica antes de
  /// confiar en él: el usuario pudo haber mandado la planilla a la
  /// papelera desde Drive, y en ese caso hay que crear otra.
  Future<String> ensureSpreadsheet(String token, {String? cachedId}) async {
    if (cachedId != null && await _existsAndUsable(token, cachedId)) {
      return cachedId;
    }
    final found = await _findSpreadsheet(token);
    if (found != null) return found;
    return _createSpreadsheet(token);
  }

  Future<bool> _existsAndUsable(String token, String id) async {
    final response = await _get(
      Uri.parse('$_driveFiles/$id?fields=id,trashed'),
      token,
      allowNotFound: true,
    );
    if (response == null) return false;
    return (response['trashed'] as bool?) != true;
  }

  Future<String?> _findSpreadsheet(String token) async {
    const query = "appProperties has { key='$_tagKey' and value='$_tagValue' } "
        'and trashed = false';
    final uri = Uri.parse(_driveFiles).replace(queryParameters: {
      'q': query,
      'fields': 'files(id,name)',
      'pageSize': '10',
    });

    final body = await _get(uri, token);
    final files = (body?['files'] as List<dynamic>?) ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String;
  }

  Future<String> _createSpreadsheet(String token) async {
    final created = await _post(
      Uri.parse(_sheetsApi),
      token,
      {
        'properties': {'title': spreadsheetTitle},
        'sheets': [
          {
            'properties': {'title': _sheetTransactions}
          },
          {
            'properties': {'title': _sheetCategories}
          },
          {
            'properties': {'title': _sheetInfo}
          },
        ],
      },
    );

    final id = created['spreadsheetId'] as String?;
    if (id == null) {
      throw SheetsBackupException('Google no devolvió el id de la planilla.');
    }

    // La etiqueta va aparte porque es un campo de Drive, no de Sheets.
    // Sin esto la planilla se vuelve imposible de reencontrar si la app
    // se reinstala y se pierde el id guardado.
    await _patch(
      Uri.parse('$_driveFiles/$id'),
      token,
      {
        'appProperties': {_tagKey: _tagValue},
      },
    );

    return id;
  }

  /// Sube el estado completo: borra lo que había y escribe todo de nuevo.
  /// No es incremental a propósito — con el volumen de esta app un dump
  /// entero es más simple de razonar y no puede quedar desincronizado.
  Future<void> upload({
    required String token,
    required String spreadsheetId,
    required List<CategoryModel> categories,
    required List<TransactionModel> transactions,
  }) async {
    await _writeTab(token, spreadsheetId, _sheetCategories, [
      _categoryHeader,
      for (final category in categories)
        [
          category.id,
          category.name,
          category.iconKey,
          category.isDefault ? 1 : 0,
        ],
    ]);

    await _writeTab(token, spreadsheetId, _sheetTransactions, [
      _transactionHeader,
      for (final tx in transactions)
        [
          tx.id,
          tx.date.toIso8601String(),
          movementTypeToString(tx.type),
          tx.amount,
          tx.categoryId,
          tx.categoryName,
          tx.categoryIconKey,
          tx.note,
        ],
    ]);

    await _writeTab(token, spreadsheetId, _sheetInfo, [
      ['clave', 'valor'],
      ['actualizado', DateTime.now().toIso8601String()],
      ['movimientos', transactions.length],
      ['categorias', categories.length],
      ['formato', _tagValue],
    ]);
  }

  /// Lee la planilla y devuelve lo que haya, ya parseado y validado.
  Future<BackupSnapshot> download({
    required String token,
    required String spreadsheetId,
  }) async {
    final categoryRows = await _readTab(token, spreadsheetId, _sheetCategories);
    final transactionRows =
        await _readTab(token, spreadsheetId, _sheetTransactions);

    return BackupSnapshot(
      categories: parseCategories(categoryRows),
      transactions: parseTransactions(transactionRows),
    );
  }

  Future<void> _writeTab(
    String token,
    String spreadsheetId,
    String tab,
    List<List<Object?>> rows,
  ) async {
    // Limpiar antes de escribir: si el respaldo nuevo tiene menos filas
    // que el anterior, sin esto quedarían movimientos fantasma al final.
    await _post(
      Uri.parse('$_sheetsApi/$spreadsheetId/values/$tab:clear'),
      token,
      const <String, Object?>{},
    );

    // `append` en vez de `update` porque agranda la grilla solo: una hoja
    // nueva viene con 1000 filas, y un `update` directo falla al pasarlas.
    final uri = Uri.parse('$_sheetsApi/$spreadsheetId/values/$tab!A1:append')
        .replace(queryParameters: {
      'valueInputOption': 'RAW',
      'insertDataOption': 'INSERT_ROWS',
    });
    await _post(uri, token, {'values': rows});
  }

  Future<List<List<dynamic>>> _readTab(
    String token,
    String spreadsheetId,
    String tab,
  ) async {
    final uri = Uri.parse('$_sheetsApi/$spreadsheetId/values/$tab').replace(
      // Sin esto los montos vuelven como texto ya formateado ("1.234")
      // y habría que deshacer el formato para recuperar el número.
      queryParameters: {'valueRenderOption': 'UNFORMATTED_VALUE'},
    );

    final body = await _get(uri, token);
    final values = (body?['values'] as List<dynamic>?) ?? const [];
    return values.map((row) => (row as List<dynamic>)).toList();
  }

  /// Expuesto para los tests: parsear es la parte que puede corromper
  /// datos reales, y se puede verificar sin red.
  List<CategoryModel> parseCategories(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    _checkHeader(rows.first, _categoryHeader, _sheetCategories);

    final categories = <CategoryModel>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isBlank(row)) continue;

      final name = _text(row, 1);
      if (name.isEmpty) continue;

      categories.add(CategoryModel(
        id: _intOrNull(row, 0),
        name: name,
        iconKey: _textOr(row, 2, 'other'),
        isDefault: _intOr(row, 3, 0) == 1,
      ));
    }
    return categories;
  }

  List<TransactionModel> parseTransactions(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    _checkHeader(rows.first, _transactionHeader, _sheetTransactions);

    final transactions = <TransactionModel>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isBlank(row)) continue;

      final rawDate = _text(row, 1);
      final date = DateTime.tryParse(rawDate);
      if (date == null) {
        throw SheetsBackupException(
          'La fila ${i + 1} de "$_sheetTransactions" tiene una fecha ilegible.',
          detail: rawDate.isEmpty ? 'vacía' : rawDate,
        );
      }

      final amount = _doubleOrNull(row, 3);
      if (amount == null) {
        throw SheetsBackupException(
          'La fila ${i + 1} de "$_sheetTransactions" tiene un monto ilegible.',
          detail: _text(row, 3),
        );
      }

      transactions.add(TransactionModel(
        id: _intOrNull(row, 0),
        date: date,
        type: movementTypeFromString(_textOr(row, 2, 'expense')),
        amount: amount,
        categoryId: _intOr(row, 4, 0),
        categoryName: _textOr(row, 5, 'Sin categoría'),
        categoryIconKey: _textOr(row, 6, 'other'),
        note: _text(row, 7),
      ));
    }
    return transactions;
  }

  /// La planilla es visible y editable en Drive: si alguien le cambió las
  /// columnas, es mejor negarse que restaurar datos corridos de lugar.
  void _checkHeader(List<dynamic> row, List<String> expected, String tab) {
    final actual = [
      for (var i = 0; i < expected.length; i++) _text(row, i).toLowerCase()
    ];
    if (actual.join(',') != expected.join(',')) {
      throw SheetsBackupException(
        'La hoja "$tab" no tiene las columnas esperadas.',
        detail: 'se esperaba: ${expected.join(', ')}',
      );
    }
  }

  bool _isBlank(List<dynamic> row) =>
      row.every((cell) => cell == null || cell.toString().trim().isEmpty);

  String _text(List<dynamic> row, int index) {
    if (index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }

  String _textOr(List<dynamic> row, int index, String fallback) {
    final value = _text(row, index);
    return value.isEmpty ? fallback : value;
  }

  int? _intOrNull(List<dynamic> row, int index) => _doubleOrNull(row, index)?.round();

  int _intOr(List<dynamic> row, int index, int fallback) =>
      _intOrNull(row, index) ?? fallback;

  /// Agrupación de miles con punto, como la escribe el campo de monto de
  /// la app: "1.234", "1.234.567". No matchea "1.5" ni "1.23".
  static final RegExp _esClThousands = RegExp(r'^\d{1,3}(\.\d{3})+$');

  double? _doubleOrNull(List<dynamic> row, int index) {
    if (index >= row.length) return null;
    final cell = row[index];
    if (cell is num) return cell.toDouble();

    // La app escribe los montos como número, así que llegar acá como
    // texto significa que alguien editó la planilla a mano, en es-CL.
    final text = cell?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    if (text.contains(',')) {
      // Con coma presente no hay ambigüedad: la coma decide los
      // decimales y los puntos son separadores de miles ("1.234,5").
      return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
    }
    if (_esClThousands.hasMatch(text)) {
      // "1.234" es mil doscientos treinta y cuatro, no 1,234: en pesos
      // chilenos el punto agrupa miles. Se exige la agrupación exacta
      // para no reinterpretar un decimal legítimo como "1.5".
      return double.tryParse(text.replaceAll('.', ''));
    }
    return double.tryParse(text);
  }

  // ---------- HTTP ----------

  Future<Map<String, dynamic>?> _get(
    Uri uri,
    String token, {
    bool allowNotFound = false,
  }) async {
    final response =
        await _send(() => _client.get(uri, headers: _headers(token)));
    if (allowNotFound && response.statusCode == 404) return null;
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(Uri uri, String token, Object body) async {
    final response = await _send(() => _client.post(
          uri,
          headers: _headers(token),
          body: jsonEncode(body),
        ));
    return _decode(response) ?? const {};
  }

  Future<Map<String, dynamic>> _patch(
      Uri uri, String token, Object body) async {
    final response = await _send(() => _client.patch(
          uri,
          headers: _headers(token),
          body: jsonEncode(body),
        ));
    return _decode(response) ?? const {};
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 30));
    } on SheetsBackupException {
      rethrow;
    } catch (e) {
      throw SheetsBackupException(
        'No se pudo conectar con Google.',
        detail: e.toString(),
      );
    }
  }

  Map<String, dynamic>? _decode(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SheetsBackupException(
        'Google rechazó el permiso. Volvé a conectar la cuenta.',
        detail: 'HTTP ${response.statusCode}',
      );
    }
    if (response.statusCode >= 400) {
      throw SheetsBackupException(
        'Google respondió con un error.',
        detail: 'HTTP ${response.statusCode}: ${_errorMessage(response.body)}',
      );
    }
    if (response.body.isEmpty) return null;

    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['message']?.toString() ?? body;
      }
    } catch (_) {
      // Un cuerpo que no es JSON igual sirve como pista tal cual viene.
    }
    return body;
  }
}
