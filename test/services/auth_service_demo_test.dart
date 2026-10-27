import 'dart:convert';

import 'package:agentreservas_conductor/providers/auth_provider.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_firma.dart';
import '../helpers/servidor_falso.dart';

AuthService _servicio(Future<http.Response> Function(http.Request) h) {
  FlutterSecureStorage.setMockInitialValues({});
  return AuthService(
    httpClient: MockClient(h),
    storage: const FlutterSecureStorage(),
    firma: FakeFirmaDispositivo(),
  );
}

void main() {
  test('el código enlaza y guarda el token como el login normal', () async {
    late http.Request visto;
    final s = _servicio((r) async {
      visto = r;
      return respuestaJson({'access_token': 'JWT-DEMO', 'nombre': 'Demo'});
    });

    final r = await s.loginDemo('123456');

    expect(r.success, isTrue);
    expect(visto.url.path, '/api/auth/conductor-demo');
    expect(jsonDecode(visto.body), {'codigo': '123456'});
    expect(visto.headers.containsKey('Authorization'), isFalse);
    expect(await s.getToken(), 'JWT-DEMO');
    expect((await s.getUserData())!['nombre'], 'Demo');
  });

  test('401: código inválido o sin simulación, sin guardar sesión', () async {
    final s = _servicio((_) async => respuestaJson({'detail': 'x'}, 401));
    final r = await s.loginDemo('000000');
    expect(r.success, isFalse);
    expect(r.error, contains('Código inválido'));
    expect(await s.isLoggedIn(), isFalse);
  });

  test('200 sin token es una respuesta inválida', () async {
    final s = _servicio((_) async => respuestaJson({'nombre': 'x'}));
    final r = await s.loginDemo('123456');
    expect(r.success, isFalse);
    expect(await s.isLoggedIn(), isFalse);
  });

  test('sin red devuelve un mensaje, no una excepción', () async {
    final s = _servicio((_) async => throw http.ClientException('sin red'));
    final r = await s.loginDemo('123456');
    expect(r.success, isFalse);
    expect(r.error, contains('Sin conexión'));
  });

  test('AuthProvider.loginDemo deja la sesión autenticada', () async {
    final auth = AuthProvider(_servicio(
        (_) async => respuestaJson({'access_token': 'T', 'nombre': 'Demo'})));
    expect(await auth.loginDemo('123456'), isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.conductorNombre, 'Demo');
  });

  test('AuthProvider.loginDemo expone el error', () async {
    final auth = AuthProvider(_servicio((_) async => respuestaJson({}, 401)));
    expect(await auth.loginDemo('111111'), isFalse);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.error, isNotNull);
  });
}
