import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agentreservas_conductor/services/api_service.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';

/// Construye un [ApiService] con token preconfigurado y un handler HTTP mock.
ApiService _makeApi({
  required Future<http.Response> Function(http.Request) handler,
  String token = 'test-jwt-token',
}) {
  FlutterSecureStorage.setMockInitialValues({
    'conductor_jwt': token,
  });
  final auth = AuthService(
    httpClient: MockClient((_) async => http.Response('', 200)),
    storage: const FlutterSecureStorage(),
  );
  return ApiService(auth, httpClient: MockClient(handler));
}

void main() {
  group('ApiService.get', () {
    test('retorna body parseado en éxito 200', () async {
      final api = _makeApi(
        handler: (req) async {
          expect(req.headers['Authorization'], 'Bearer test-jwt-token');
          return http.Response(
            jsonEncode({'viajes': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final result = await api.get('/api/conductor/mis-viajes');
      expect(result['viajes'], isEmpty);
    });

    test('lanza ApiException en 401', () async {
      final api = _makeApi(
        handler: (_) async => http.Response(
          jsonEncode({'detail': 'Token expirado'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        () => api.get('/api/conductor/mis-viajes'),
        throwsA(
          predicate<ApiException>(
              (e) => e.statusCode == 401 && e.message == 'Token expirado'),
        ),
      );
    });

    test('lanza ApiException en 404', () async {
      final api = _makeApi(
        handler: (_) async => http.Response(
          jsonEncode({'detail': 'No encontrado'}),
          404,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        () => api.get('/api/conductor/viajes/999'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('ApiService.post', () {
    test('envía JSON body y retorna respuesta', () async {
      final api = _makeApi(
        handler: (req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['estado'], 'NORMAL');
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final result = await api.post(
        '/api/conductor/viajes/1/chequeo',
        body: {'estado': 'NORMAL', 'lat': 4.6, 'lng': -74.0, 'dia_numero': 1},
      );
      expect(result['ok'], isTrue);
    });

    test('post sin body no lanza excepción', () async {
      final api = _makeApi(
        handler: (_) async => http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final result = await api.post('/api/conductor/viajes/1/iniciar-viaje');
      expect(result['ok'], isTrue);
    });

    test('lanza ApiException 403 con mensaje del servidor', () async {
      final api = _makeApi(
        handler: (_) async => http.Response(
          jsonEncode({'detail': 'Sin permiso'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        () => api.post('/api/conductor/viajes/1/cerrar-viaje'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', 'Sin permiso'),
        ),
      );
    });
  });

  group('ApiService — endpoints específicos', () {
    test('getMisViajes retorna lista vacía', () async {
      final api = _makeApi(
        handler: (_) async => http.Response(
          jsonEncode({'viajes': []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final viajes = await api.getMisViajes();
      expect(viajes, isEmpty);
    });

    test('getMisViajes retorna lista con un viaje', () async {
      final api = _makeApi(
        handler: (_) async => http.Response(
          jsonEncode({
            'viajes': [
              {'id': 1, 'token': 'TRP-001', 'estado': 'APROBADO'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final viajes = await api.getMisViajes();
      expect(viajes, hasLength(1));
      expect((viajes.first as Map)['token'], 'TRP-001');
    });

    test('cerrarDia envía dia_numero y enviar_revision correctamente', () async {
      final api = _makeApi(
        handler: (req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['dia_numero'], 2);
          expect(body['enviar_revision'], isTrue);
          return http.Response(
            jsonEncode({'ok': true, 'total': 45000}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final result = await api.cerrarDia(
        1,
        diaNumero: 2,
        enviarRevision: true,
      );
      expect(result['ok'], isTrue);
    });

    test('ApiException.toString incluye statusCode y mensaje', () {
      const e = ApiException(422, 'monto inválido');
      expect(e.toString(), contains('422'));
      expect(e.toString(), contains('monto inválido'));
    });
  });

  group('ApiService — JWT en headers', () {
    test('JWT se incluye en Authorization header', () async {
      String? capturedAuth;
      final api = _makeApi(
        token: 'mi-token-especial',
        handler: (req) async {
          capturedAuth = req.headers['Authorization'];
          return http.Response(
            jsonEncode({'viajes': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      await api.getMisViajes();
      expect(capturedAuth, 'Bearer mi-token-especial');
    });
  });
}
