import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:agentreservas_conductor/services/ws_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AuthService _makeAuth({String? token}) {
  FlutterSecureStorage.setMockInitialValues(
    token != null ? {'conductor_jwt': token} : {},
  );
  return AuthService(
    httpClient: MockClient((_) async => http.Response('', 200)),
    storage: const FlutterSecureStorage(),
  );
}

void main() {
  group('WsMensaje.fromJson', () {
    test('CHEQUEO_REQUEST parseado correctamente', () {
      final msg = WsMensaje.fromJson({'tipo': 'CHEQUEO_REQUEST'});
      expect(msg.tipo, WsMensajeTipo.chequeoRequest);
    });

    test('VIAJE_CONFIRMADO parseado correctamente', () {
      final msg = WsMensaje.fromJson({
        'tipo': 'VIAJE_CONFIRMADO',
        'mensaje': 'Confirmado',
      });
      expect(msg.tipo, WsMensajeTipo.viajeConfirmado);
      expect(msg.data['mensaje'], 'Confirmado');
    });

    test('APROBACION_CHECKLIST parseado correctamente', () {
      final msg = WsMensaje.fromJson({
        'tipo': 'APROBACION_CHECKLIST',
        'estado': 'APROBADO',
        'mensaje': 'OK',
      });
      expect(msg.tipo, WsMensajeTipo.aprobacionChecklist);
      expect(msg.data['estado'], 'APROBADO');
    });

    test('APROBACION_SOPORTE parseado correctamente', () {
      final msg = WsMensaje.fromJson({
        'tipo': 'APROBACION_SOPORTE',
        'soporte_id': 5,
        'estado': 'RECHAZADO',
      });
      expect(msg.tipo, WsMensajeTipo.aprobacionSoporte);
      expect(msg.data['soporte_id'], 5);
    });

    test('NOTIFICACION parseada correctamente', () {
      final msg =
          WsMensaje.fromJson({'tipo': 'NOTIFICACION', 'texto': 'Aviso'});
      expect(msg.tipo, WsMensajeTipo.notificacion);
    });

    test('tipo desconocido → WsMensajeTipo.desconocido', () {
      final msg = WsMensaje.fromJson({'tipo': 'INEXISTENTE'});
      expect(msg.tipo, WsMensajeTipo.desconocido);
    });

    test('sin campo tipo → desconocido sin lanzar excepción', () {
      final msg = WsMensaje.fromJson({'otro': 'campo'});
      expect(msg.tipo, WsMensajeTipo.desconocido);
    });
  });

  group('WsService — estado sin conexión', () {
    test('isConnected = false antes de conectar', () {
      final auth = _makeAuth(token: 'tok');
      final ws = WsService(auth);
      expect(ws.isConnected, isFalse);
    });

    test('stream existe antes de conectar (no lanza)', () {
      final auth = _makeAuth(token: 'tok');
      final ws = WsService(auth);
      expect(ws.stream, isNotNull);
    });

    test('disconnect sin conexión previa no lanza excepción', () async {
      final auth = _makeAuth();
      final ws = WsService(auth);
      await expectLater(ws.disconnect(), completes);
    });
  });
}
