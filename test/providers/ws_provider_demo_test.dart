import 'dart:async';

import 'package:agentreservas_conductor/providers/ws_provider.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:agentreservas_conductor/services/ubicacion_fuente.dart';
import 'package:agentreservas_conductor/services/ws_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWs extends WsService {
  _FakeWs(super.auth);
  final _c = StreamController<WsMensaje>.broadcast();
  @override
  Stream<WsMensaje> get stream => _c.stream;
  @override
  Future<void> connect(int solicitudId) async {}
  @override
  Future<void> disconnect() async {}
  void emitir(Map<String, dynamic> json) => _c.add(WsMensaje.fromJson(json));
}

void main() {
  late _FakeWs ws;
  late PosicionSimulada simulada;
  late WsProvider provider;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ws = _FakeWs(AuthService(storage: const FlutterSecureStorage()));
    simulada = PosicionSimulada();
    provider = WsProvider(ws, simulada: simulada);
    await provider.conectar(1);
  });

  group('mensajes del servidor', () {
    test('se reconocen TRAMO_PROHIBIDO y POSICION_VEHICULO', () {
      expect(WsMensaje.fromJson({'tipo': 'TRAMO_PROHIBIDO'}).tipo,
          WsMensajeTipo.tramoProhibido);
      expect(WsMensaje.fromJson({'tipo': 'POSICION_VEHICULO'}).tipo,
          WsMensajeTipo.posicionVehiculo);
      expect(WsMensaje.fromJson({'tipo': 'POSICION'}).tipo,
          WsMensajeTipo.posicionVehiculo);
    });
  });

  group('aviso de tramo prohibido', () {
    test('guarda el mensaje y la alternativa para avisar al conductor',
        () async {
      ws.emitir({
        'tipo': 'TRAMO_PROHIBIDO',
        'mensaje': 'Entraste a un tramo prohibido',
        'alternativa': 'Vía Maicao',
      });
      await Future<void>.delayed(Duration.zero);

      expect(provider.tramoProhibido, isTrue);
      expect(provider.mensajeTramoProhibido, 'Entraste a un tramo prohibido');
      expect(provider.alternativaTramo, 'Vía Maicao');

      provider.limpiarTramoProhibido();
      expect(provider.tramoProhibido, isFalse);
      expect(provider.alternativaTramo, isNull);
    });

    test('alternativa vacía se toma como ausente', () async {
      ws.emitir({'tipo': 'TRAMO_PROHIBIDO', 'mensaje': 'x', 'alternativa': ''});
      await Future<void>.delayed(Duration.zero);
      expect(provider.alternativaTramo, isNull);
    });
  });

  group('posición del vehículo simulado', () {
    test('se guarda, forma el rastro y alimenta la fuente demo', () async {
      ws.emitir({'tipo': 'POSICION_VEHICULO', 'lat': 10.77, 'lng': -73.0});
      ws.emitir({'tipo': 'POSICION_VEHICULO', 'lat': 10.78, 'lng': -73.01});
      await Future<void>.delayed(Duration.zero);

      expect(provider.posicionVehiculo!.lat, 10.78);
      expect(provider.rastro.length, 2);
      final p = await UbicacionDemo(simulada).posicionAhora();
      expect([p!.lat, p.lng], [10.78, -73.01]);
    });

    test('un mensaje sin coordenadas válidas se ignora', () async {
      ws.emitir({'tipo': 'POSICION_VEHICULO', 'lat': 'x', 'lng': null});
      await Future<void>.delayed(Duration.zero);
      expect(provider.posicionVehiculo, isNull);
      expect(provider.rastro, isEmpty);
    });

    test('al reconectar se borra el rastro anterior', () async {
      ws.emitir({'tipo': 'POSICION_VEHICULO', 'lat': 10.77, 'lng': -73.0});
      await Future<void>.delayed(Duration.zero);
      await provider.conectar(1);
      expect(provider.rastro, isEmpty);
      expect(simulada.ultima, isNull);
    });
  });
}
