import 'package:google_sign_in/google_sign_in.dart';

/// Resultado de intentar conectar la cuenta de Google. Distingue el
/// "cancelé yo" del "está mal configurado", porque en pantalla no se
/// comunican igual: lo primero no es un error, lo segundo sí.
enum GoogleAuthOutcome { connected, canceled, notConfigured, failed }

class GoogleAuthResult {
  const GoogleAuthResult(this.outcome, {this.account, this.detail});

  final GoogleAuthOutcome outcome;
  final GoogleSignInAccount? account;

  /// Motivo técnico, para mostrar debajo del mensaje amable.
  final String? detail;

  bool get isConnected => outcome == GoogleAuthOutcome.connected;
}

/// Login con Google, usado como identidad para el respaldo en Sheets.
///
/// La app funciona completa sin pasar por acá: nada de lo que vive en
/// SQLite depende de haber iniciado sesión.
class GoogleAuthService {
  GoogleAuthService({GoogleSignIn? signIn})
      : _signIn = signIn ?? GoogleSignIn.instance;

  /// Acceso por archivo a Drive: la app solo ve la planilla que ella
  /// misma creó, nunca el resto del Drive. Es un scope "no sensible", así
  /// que no hay proceso de verificación de Google ni pantalla de
  /// advertencia para el usuario.
  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
  ];

  final GoogleSignIn _signIn;

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get account => _account;

  bool _initialized = false;

  /// Queda en true si falta el `GIDClientID` del Info.plist (o el
  /// `serverClientId` en Android). Sin eso el login no puede ni empezar,
  /// y conviene decirlo en vez de mostrar un error genérico.
  bool _missingConfiguration = false;
  bool get isMissingConfiguration => _missingConfiguration;

  /// Arranca el SDK y, si ya había una sesión, la recupera sin mostrar
  /// nada. Devuelve la cuenta recuperada, o null si hay que loguearse.
  Future<GoogleSignInAccount?> initializeAndRestore() async {
    try {
      if (!_initialized) {
        await _signIn.initialize();
        _initialized = true;
      }
      // El tipo de retorno es un Future nullable: hay plataformas donde
      // la sesión llega por el stream de eventos y acá no hay nada que
      // esperar.
      final attempt = _signIn.attemptLightweightAuthentication();
      if (attempt == null) return null;
      _account = await attempt;
      return _account;
    } on GoogleSignInException catch (e) {
      _missingConfiguration =
          e.code == GoogleSignInExceptionCode.clientConfigurationError;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Login explícito, con selector de cuenta. Pide los scopes como
  /// `scopeHint` para resolver todo en una sola pantalla en vez de
  /// encadenar dos diálogos.
  Future<GoogleAuthResult> connect() async {
    try {
      if (!_initialized) {
        await _signIn.initialize();
        _initialized = true;
      }
      if (!_signIn.supportsAuthenticate()) {
        return const GoogleAuthResult(
          GoogleAuthOutcome.notConfigured,
          detail: 'Esta plataforma no soporta el login de Google.',
        );
      }

      final account = await _signIn.authenticate(scopeHint: scopes);
      // Sin esto el token para Sheets puede no estar autorizado todavía:
      // `scopeHint` es una sugerencia, no una garantía.
      await account.authorizationClient.authorizeScopes(scopes);

      _account = account;
      _missingConfiguration = false;
      return GoogleAuthResult(GoogleAuthOutcome.connected, account: account);
    } on GoogleSignInException catch (e) {
      return GoogleAuthResult(_outcomeFor(e.code), detail: e.description);
    } catch (e) {
      return GoogleAuthResult(GoogleAuthOutcome.failed, detail: e.toString());
    }
  }

  GoogleAuthOutcome _outcomeFor(GoogleSignInExceptionCode code) {
    switch (code) {
      case GoogleSignInExceptionCode.canceled:
        return GoogleAuthOutcome.canceled;
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        _missingConfiguration = true;
        return GoogleAuthOutcome.notConfigured;
      default:
        return GoogleAuthOutcome.failed;
    }
  }

  /// Token para llamar a Sheets y Drive.
  ///
  /// Con [interactive] en false no muestra nada: es lo que usa el
  /// respaldo automático, que no debe interrumpir a nadie. Si devuelve
  /// null, el respaldo queda pendiente hasta que el usuario entre a
  /// Ajustes.
  Future<String?> accessToken({bool interactive = false}) async {
    final account = _account;
    if (account == null) return null;

    try {
      final cached =
          await account.authorizationClient.authorizationForScopes(scopes);
      if (cached != null) return cached.accessToken;
      if (!interactive) return null;

      final granted =
          await account.authorizationClient.authorizeScopes(scopes);
      return granted.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        _missingConfiguration = true;
      }
      return null;
    }
  }

  Future<void> disconnect() async {
    _account = null;
    try {
      await _signIn.signOut();
    } catch (_) {
      // Desconectarse nunca debería dejar la app en un estado raro: si el
      // SDK falla, igual soltamos la cuenta de este lado.
    }
  }
}
