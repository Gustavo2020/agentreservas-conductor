import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'firma_dispositivo.dart';
import 'log_service.dart';

/// Resultado del intento de login.
class LoginResult {
  final bool success;
  final String? token;
  final Map<String, dynamic>? userData;
  final String? error;

  const LoginResult({
    required this.success,
    this.token,
    this.userData,
    this.error,
  });
}

/// Gestiona autenticación y almacenamiento seguro del JWT.
/// El token se guarda ÚNICAMENTE en flutter_secure_storage (Android Keystore).
///
/// El ingreso tiene dos factores: la contraseña y la llave del aparato. La
/// contraseña sola NUNCA da sesión:
///   1. `conductor-login` verifica la clave y dice qué sigue.
///   2. Primer ingreso: se crea la llave del aparato y se enrola (`enrolar`).
///   3. Siguientes: se firma un reto con la llave (`firmar`).
class AuthService {
  final http.Client _httpClient;
  final FlutterSecureStorage _storage;
  final FirmaDispositivo _firma;

  AuthService({
    http.Client? httpClient,
    FlutterSecureStorage? storage,
    FirmaDispositivo? firma,
  })  : _httpClient = httpClient ?? http.Client(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _firma = firma ?? FirmaDispositivoBiometrica();

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<LoginResult> login(String email, String password) async {
    AppLogger.info('Login: intento', context: {'email': email});
    try {
      final dispositivoId = await getDispositivoId();
      final response = await _post('/api/auth/conductor-login', {
        'email': email,
        'password': password,
        if (dispositivoId != null) 'dispositivo_id': dispositivoId,
      });
      final body = _decodificar(response);

      if (response.statusCode == 200) {
        switch (body['step']) {
          case 'enrolar':
            return _enrolar(body['session'] as String, email);
          case 'firmar':
            return _firmar(body, email);
        }
        AppLogger.warning('Login: paso desconocido', context: {'email': email});
        return const LoginResult(
          success: false,
          error: 'Respuesta inválida del servidor',
        );
      }

      if (response.statusCode == 401) {
        AppLogger.warning('Login: credenciales incorrectas',
            context: {'email': email, 'status': '401'});
        return const LoginResult(
          success: false,
          error: 'Credenciales incorrectas',
        );
      }
      if (response.statusCode == 403) {
        // El servidor dice por qué (sin permiso, sin registro de conductor o
        // aparato no registrado) solo a quien ya probó la clave.
        AppLogger.warning('Login: acceso denegado',
            context: {'email': email, 'status': '403'});
        return LoginResult(
          success: false,
          error:
              body['detail'] as String? ?? 'No tienes acceso a esta aplicación',
        );
      }

      final detail = body['detail'] as String? ?? 'Error desconocido';
      AppLogger.warning('Login: error HTTP',
          context: {'email': email, 'status': '${response.statusCode}'});
      return LoginResult(success: false, error: detail);
    } on Exception catch (e, st) {
      AppLogger.error('Login: error de conexión', e,
          stackTrace: st, context: {'email': email});
      return LoginResult(success: false, error: 'Error de conexión: $e');
    }
  }

  // ── Segundo factor ─────────────────────────────────────────────────────────

  /// Primer ingreso de este teléfono: crea la llave y la registra.
  Future<LoginResult> _enrolar(String session, String email) async {
    // Si quedó una llave de una instalación anterior (aparato revocado), se
    // reemplaza: la del servidor ya no existe y esa no serviría.
    if (await _firma.existeLlave()) await _firma.borrarLlave();

    final llave = await _firma.crearLlave();
    if (!llave.ok) return LoginResult(success: false, error: llave.error);

    final response = await _post('/api/auth/conductor-enrolar', {
      'session': session,
      'nombre': AppConfig.nombreDispositivo,
      'llave_publica': llave.valor,
    });
    if (response.statusCode != 200) {
      // Sin enrolar en el servidor la llave local no sirve: se descarta.
      await _firma.borrarLlave();
      return _errorDePaso(response, email, 'enrolar');
    }
    return _guardarSesion(_decodificar(response), email);
  }

  /// Ingresos siguientes: firma el reto con la llave del aparato.
  Future<LoginResult> _firmar(Map<String, dynamic> paso, String email) async {
    final reto = paso['reto'] as String;
    // Lo firmado es EXACTAMENTE dominio + bytes del reto; el servidor verifica
    // lo mismo. El dominio evita que esta llave firme otra cosa por error.
    final mensaje = Uint8List.fromList([
      ...utf8.encode(AppConfig.dominioFirma),
      ...base64Decode(reto),
    ]);
    final firma = await _firma.firmar(mensaje);
    if (!firma.ok) return LoginResult(success: false, error: firma.error);

    final response = await _post('/api/auth/conductor-firmar', {
      'session': paso['session'],
      'dispositivo_id': paso['dispositivo_id'],
      'reto': reto,
      'firma': firma.valor,
    });
    if (response.statusCode != 200) {
      return _errorDePaso(response, email, 'firmar');
    }
    return _guardarSesion(_decodificar(response), email);
  }

  LoginResult _errorDePaso(http.Response response, String email, String paso) {
    AppLogger.warning('Login: paso $paso rechazado',
        context: {'email': email, 'status': '${response.statusCode}'});
    if (response.statusCode == 401) {
      return const LoginResult(
        success: false,
        error: 'No se pudo verificar tu teléfono. Inténtalo de nuevo',
      );
    }
    final detail = _decodificar(response)['detail'];
    return LoginResult(
      success: false,
      error: detail is String ? detail : 'No se pudo completar el ingreso',
    );
  }

  Future<LoginResult> _guardarSesion(
    Map<String, dynamic> body,
    String email,
  ) async {
    final token = body['access_token'] as String?;
    if (token == null) {
      AppLogger.warning('Login: token ausente en respuesta 200',
          context: {'email': email});
      return const LoginResult(
        success: false,
        error: 'Respuesta inválida del servidor',
      );
    }
    await _saveToken(token, body);
    final id = body['dispositivo_id'];
    if (id is int) {
      await _storage.write(key: AppConfig.dispositivoIdKey, value: '$id');
    }
    AppLogger.info('Login: exitoso', context: {'email': email});
    return LoginResult(success: true, token: token, userData: body);
  }

  Future<http.Response> _post(String ruta, Map<String, dynamic> cuerpo) {
    return _httpClient
        .post(
          Uri.parse('${AppConfig.baseUrl}$ruta'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(cuerpo),
        )
        .timeout(AppConfig.httpTimeout);
  }

  Map<String, dynamic> _decodificar(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  /// Identificador del aparato enrolado, o null si aún no se enroló.
  Future<int?> getDispositivoId() async {
    final raw = await _storage.read(key: AppConfig.dispositivoIdKey);
    return raw == null ? null : int.tryParse(raw);
  }

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<void> _saveToken(
    String token,
    Map<String, dynamic> userData,
  ) async {
    await _storage.write(key: AppConfig.jwtStorageKey, value: token);
    await _storage.write(
      key: AppConfig.userDataKey,
      value: jsonEncode(userData),
    );
  }

  Future<String?> getToken() async {
    return _storage.read(key: AppConfig.jwtStorageKey);
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final raw = await _storage.read(key: AppConfig.userDataKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Elimina el JWT y datos de usuario del secure storage. NO toca el aparato
  /// enrolado ni su llave: cerrar sesión no es perder el segundo factor.
  Future<void> logout() async {
    await _storage.delete(key: AppConfig.jwtStorageKey);
    await _storage.delete(key: AppConfig.userDataKey);
  }

  void dispose() => _httpClient.close();
}
