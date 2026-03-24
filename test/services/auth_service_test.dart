import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';

/// Crea un AuthService con storage en memoria (sin Keystore real) y
/// un MockClient HTTP que responde según la función [handler].
AuthService _makeService({
  required Future<http.Response> Function(http.Request) handler,
  Map<String, String> initialStorage = const {},
}) {
  FlutterSecureStorage.setMockInitialValues(Map.from(initialStorage));

  return AuthService(
    httpClient: MockClient(handler),
    storage: const FlutterSecureStorage(),
  );
}

void main() {
  group('AuthService.login', () {
    test('login exitoso guarda token y retorna success=true', () async {
      const fakeToken = 'eyJhbGciOiJIUzI1NiJ9.test.sig';
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({
            'access_token': fakeToken,
            'nombre': 'Juan Conductor',
            'nivel': 12,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final result = await service.login('juan@geb.com', 'password123');

      expect(result.success, isTrue);
      expect(result.token, fakeToken);
      expect(result.error, isNull);
      expect(result.userData?['nombre'], 'Juan Conductor');

      // El token se persiste
      final stored = await service.getToken();
      expect(stored, fakeToken);
    });

    test('401 retorna error "Credenciales incorrectas"', () async {
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({'detail': 'Invalid credentials'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );

      final result = await service.login('x@geb.com', 'wrong');

      expect(result.success, isFalse);
      expect(result.error, 'Credenciales incorrectas');
    });

    test('403 retorna error "No tienes acceso"', () async {
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({'detail': 'forbidden'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );

      final result = await service.login('x@geb.com', 'pass');

      expect(result.success, isFalse);
      expect(result.error, contains('No tienes acceso'));
    });

    test('respuesta 200 sin access_token retorna error', () async {
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({'nombre': 'sin token'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final result = await service.login('x@geb.com', 'pass');

      expect(result.success, isFalse);
      expect(result.error, contains('inválida'));
    });

    test('excepción de red retorna error de conexión', () async {
      final service = _makeService(
        handler: (_) async => throw Exception('Connection refused'),
      );

      final result = await service.login('x@geb.com', 'pass');

      expect(result.success, isFalse);
      expect(result.error, contains('Error de conexión'));
    });
  });

  group('AuthService.isLoggedIn / logout', () {
    test('isLoggedIn = false cuando storage vacío', () async {
      final service = _makeService(handler: (_) async => http.Response('', 200));
      expect(await service.isLoggedIn(), isFalse);
    });

    test('isLoggedIn = true después de login exitoso', () async {
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({'access_token': 'tok', 'nombre': 'C'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await service.login('x@geb.com', 'pass');
      expect(await service.isLoggedIn(), isTrue);
    });

    test('logout limpia el token del storage', () async {
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({'access_token': 'tok', 'nombre': 'C'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await service.login('x@geb.com', 'pass');
      expect(await service.isLoggedIn(), isTrue);

      await service.logout();

      expect(await service.isLoggedIn(), isFalse);
      expect(await service.getToken(), isNull);
      expect(await service.getUserData(), isNull);
    });
  });

  group('AuthService.getUserData', () {
    test('retorna null cuando no hay datos guardados', () async {
      final service = _makeService(handler: (_) async => http.Response('', 200));
      expect(await service.getUserData(), isNull);
    });

    test('retorna datos completos tras login', () async {
      final service = _makeService(
        handler: (_) async => http.Response(
          jsonEncode({
            'access_token': 'tok',
            'nombre': 'Ana',
            'nivel': 12,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await service.login('ana@geb.com', 'pass');
      final data = await service.getUserData();
      expect(data?['nombre'], 'Ana');
      expect(data?['nivel'], 12);
    });
  });
}
