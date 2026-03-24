import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
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
class AuthService {
  final http.Client _httpClient;
  final FlutterSecureStorage _storage;

  AuthService({
    http.Client? httpClient,
    FlutterSecureStorage? storage,
  })  : _httpClient = httpClient ?? http.Client(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<LoginResult> login(String email, String password) async {
    AppLogger.info('Login: intento', context: {'email': email});
    try {
      final response = await _httpClient
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/auth/conductor-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(AppConfig.httpTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
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
        AppLogger.info('Login: exitoso', context: {'email': email});
        return LoginResult(success: true, token: token, userData: body);
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
        AppLogger.warning('Login: acceso denegado',
            context: {'email': email, 'status': '403'});
        return const LoginResult(
          success: false,
          error: 'No tienes acceso a esta aplicación',
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

  /// Elimina el JWT y datos de usuario del secure storage.
  Future<void> logout() async {
    await _storage.delete(key: AppConfig.jwtStorageKey);
    await _storage.delete(key: AppConfig.userDataKey);
  }

  void dispose() => _httpClient.close();
}
