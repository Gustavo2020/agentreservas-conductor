import 'dart:convert';

import 'package:agentreservas_conductor/providers/viaje_provider.dart';
import 'package:agentreservas_conductor/services/api_service.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiService _makeApi(Future<http.Response> Function(http.Request) handler) {
  FlutterSecureStorage.setMockInitialValues({'conductor_jwt': 'tok'});
  final auth = AuthService(
    httpClient: MockClient((_) async => http.Response('', 200)),
    storage: const FlutterSecureStorage(),
  );
  return ApiService(auth, httpClient: MockClient(handler));
}

void main() {
  group('ViajeProvider.cargarMisViajes', () {
    test('popula viajes en éxito', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({
            'viajes': [
              {'id': 1, 'token': 'TRP-001', 'estado': 'APROBADO'},
              {'id': 2, 'token': 'TRP-002', 'estado': 'EN_CURSO'},
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);

      await provider.cargarMisViajes();

      expect(provider.viajes, hasLength(2));
      expect(provider.viajes.first.token, 'TRP-001');
      expect(provider.viajes.last.estado, 'EN_CURSO');
      expect(provider.error, isNull);
      expect(provider.loading, isFalse);
    });

    test('error HTTP → error no nulo, lista vacía', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'detail': 'Unauthorized'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);

      await provider.cargarMisViajes();

      expect(provider.viajes, isEmpty);
      expect(provider.error, isNotNull);
    });

    test('lista vacía del servidor → lista vacía sin error', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'viajes': []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);
      await provider.cargarMisViajes();

      expect(provider.viajes, isEmpty);
      expect(provider.error, isNull);
    });
  });

  group('ViajeProvider.cargarDetalleViaje', () {
    test('popula viajeActual con trayectos y checklist', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({
            'detalle': {'id': 5, 'token': 'TRP-005', 'estado': 'EN_CURSO'},
            'trayectos': [
              {
                'id': 1,
                'dia_numero': 1,
                'origen_municipio': 'Bogotá',
                'destino_municipio': 'Cali'
              }
            ],
            'checklist': null,
            'cierres': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);

      await provider.cargarDetalleViaje(5);

      expect(provider.viajeActual, isNotNull);
      expect(provider.viajeActual!.token, 'TRP-005');
      expect(provider.viajeActual!.trayectos, hasLength(1));
    });
  });

  group('ViajeProvider.aceptarRuta', () {
    test('retorna true en éxito', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);
      expect(await provider.aceptarRuta(1), isTrue);
    });

    test('retorna false en error y guarda error', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'detail': 'Viaje no encontrado'}),
          404,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);
      expect(await provider.aceptarRuta(99), isFalse);
      expect(provider.error, isNotNull);
    });
  });

  group('ViajeProvider.cargarSoportesDia', () {
    test('popula soportesDia y totalDia', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({
            'soportes': [
              {
                'id': 1,
                'solicitud_viaje_id': 10,
                'dia_numero': 1,
                'tipo': 'PEAJE',
                'monto': 8500,
                'foto_soporte': 'p.jpg',
                'estado': 'APROBADO',
              },
            ],
            'total_dia': 8500.0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);

      await provider.cargarSoportesDia(10, 1);

      expect(provider.soportesDia, hasLength(1));
      expect(provider.soportesDia.first.tipo, 'PEAJE');
      expect(provider.totalDia, 8500.0);
    });
  });

  group('ViajeProvider.cerrarDia', () {
    test('retorna true en éxito', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'total': 12000}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);
      expect(
        await provider.cerrarDia(1, diaNumero: 1, enviarRevision: false),
        isTrue,
      );
    });

    test('error 400 (soportes pendientes) retorna false con error', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'detail': 'El día ya fue cerrado previamente'}),
          400,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);
      expect(
        await provider.cerrarDia(1, diaNumero: 1, enviarRevision: true),
        isFalse,
      );
      expect(provider.error, contains('cerrado'));
    });
  });

  group('ViajeProvider.cerrarViaje', () {
    test('retorna true cuando soportes y días están OK', () async {
      final api = _makeApi(
        (_) async => http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = ViajeProvider(api);
      expect(await provider.cerrarViaje(1), isTrue);
    });
  });
}
