import 'dart:convert';

import 'package:agentreservas_conductor/providers/auth_provider.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AuthService _makeAuth(Future<http.Response> Function(http.Request) handler) {
  FlutterSecureStorage.setMockInitialValues({});
  return AuthService(
    httpClient: MockClient(handler),
    storage: const FlutterSecureStorage(),
  );
}

void main() {
  group('AuthProvider — estado inicial', () {
    test('estado inicial es AuthState.unknown', () {
      final auth = _makeAuth((_) async => http.Response('', 200));
      final provider = AuthProvider(auth);
      expect(provider.state, AuthState.unknown);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });
  });

  group('AuthProvider.checkAuth', () {
    test('sin token → estado unauthenticated', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = AuthService(
        httpClient: MockClient((_) async => http.Response('', 200)),
        storage: const FlutterSecureStorage(),
      );
      final provider = AuthProvider(auth);

      await provider.checkAuth();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
    });

    test('con token en storage → estado authenticated', () async {
      FlutterSecureStorage.setMockInitialValues({
        'conductor_jwt': 'tok',
        'conductor_user': jsonEncode({'nombre': 'Carlos'}),
      });
      final auth = AuthService(
        httpClient: MockClient((_) async => http.Response('', 200)),
        storage: const FlutterSecureStorage(),
      );
      final provider = AuthProvider(auth);

      await provider.checkAuth();

      expect(provider.state, AuthState.authenticated);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.conductorNombre, 'Carlos');
    });
  });

  group('AuthProvider.login', () {
    test('login exitoso cambia estado a authenticated', () async {
      final auth = _makeAuth(
        (_) async => http.Response(
          jsonEncode({'access_token': 'jwt123', 'nombre': 'Pedro'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = AuthProvider(auth);

      final ok = await provider.login('pedro@geb.com', 'pass');

      expect(ok, isTrue);
      expect(provider.state, AuthState.authenticated);
      expect(provider.error, isNull);
      expect(provider.conductorNombre, 'Pedro');
    });

    test('login fallido → estado unauthenticated con error', () async {
      final auth = _makeAuth(
        (_) async => http.Response(
          jsonEncode({'detail': 'bad creds'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = AuthProvider(auth);

      final ok = await provider.login('x@geb.com', 'wrong');

      expect(ok, isFalse);
      expect(provider.state, AuthState.unauthenticated);
      expect(provider.error, isNotNull);
    });

    test('loading es true durante el login y false al terminar', () async {
      bool wasLoading = false;
      final auth = _makeAuth(
        (_) async {
          await Future.delayed(const Duration(milliseconds: 10));
          return http.Response(
            jsonEncode({'access_token': 'tok', 'nombre': 'X'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      final provider = AuthProvider(auth);

      provider.addListener(() {
        if (provider.loading) wasLoading = true;
      });

      await provider.login('x@geb.com', 'pass');

      expect(wasLoading, isTrue);
      expect(provider.loading, isFalse);
    });
  });

  group('AuthProvider.logout', () {
    test('logout limpia estado y vuelve a unauthenticated', () async {
      final auth = _makeAuth(
        (_) async => http.Response(
          jsonEncode({'access_token': 'tok', 'nombre': 'Ana'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = AuthProvider(auth);
      await provider.login('ana@geb.com', 'pass');
      expect(provider.isAuthenticated, isTrue);

      await provider.logout();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.userData, isNull);
    });
  });

  group('AuthProvider.conductorNombre', () {
    test('retorna "Conductor" cuando no hay datos de usuario', () {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = AuthService(
        httpClient: MockClient((_) async => http.Response('', 200)),
        storage: const FlutterSecureStorage(),
      );
      final provider = AuthProvider(auth);
      expect(provider.conductorNombre, 'Conductor');
    });
  });
}
