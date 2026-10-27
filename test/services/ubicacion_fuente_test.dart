import 'dart:async';

import 'package:agentreservas_conductor/config/app_config.dart';
import 'package:agentreservas_conductor/services/cola_posiciones.dart';
import 'package:agentreservas_conductor/services/panico_service.dart';
import 'package:agentreservas_conductor/services/seguimiento_controller.dart';
import 'package:agentreservas_conductor/services/seguimiento_service.dart';
import 'package:agentreservas_conductor/services/ubicacion_fuente.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _Memoria implements AlmacenCola {
  @override
  Future<String?> leer() async => null;
  @override
  Future<void> guardar(String c) async {}
}

void main() {
  test('la APK normal no está en modo demo', () {
    expect(AppConfig.modoDemo, isFalse);
  });

  group('UbicacionDemo', () {
    test('no pide permisos ni depende del GPS', () async {
      final f = UbicacionDemo(PosicionSimulada());
      expect(f.esDemo, isTrue);
      expect(await f.pedirPermiso(), LocationPermission.always);
      expect(await f.gpsEncendido(), isTrue);
      expect(await f.flujo().isEmpty, isTrue);
    });

    test('sin posición del servidor usa el punto de partida de la demo',
        () async {
      final f = UbicacionDemo(PosicionSimulada());
      final p = await f.posicionAhora();
      expect(p!.lat, AppConfig.demoLatInicial);
      expect(p.lng, AppConfig.demoLngInicial);
    });

    test('devuelve la última posición que mandó el servidor', () async {
      final sim = PosicionSimulada()
        ..ultima = MuestraGps(11.5, -72.9, DateTime(2026));
      final p = await UbicacionDemo(sim).posicionAhora();
      expect([p!.lat, p.lng], [11.5, -72.9]);
    });
  });

  group('SeguimientoController en demo', () {
    test('no abre el flujo del GPS ni pide permisos', () async {
      var flujoAbierto = false;
      final seguimiento = SeguimientoService(
        cola: ColaPosiciones(_Memoria()),
        abrirFlujo: () {
          flujoAbierto = true;
          return const Stream<MuestraGps>.empty();
        },
        enviarLote: (id, p) async => ResultadoLote.recibido,
        cadaLote: const Duration(hours: 1),
      );
      final c = SeguimientoController(
        ubicacion: UbicacionDemo(PosicionSimulada()),
        seguimiento: seguimiento,
        panico: PanicoService(enviar: (id, lat, lng) async {
          return ResultadoPanico.confirmado;
        }),
      );

      expect(await c.iniciar(5), ArranqueSeguimiento.activo);
      expect(flujoAbierto, isFalse);
      expect(seguimiento.activo, isFalse);
    });

    test('el pánico usa la posición simulada del vehículo', () async {
      final enviados = <List<double>>[];
      final sim = PosicionSimulada()
        ..ultima = MuestraGps(10.9, -73.1, DateTime.now());
      final c = SeguimientoController(
        ubicacion: UbicacionDemo(sim),
        seguimiento: SeguimientoService(
          cola: ColaPosiciones(_Memoria()),
          abrirFlujo: () => const Stream<MuestraGps>.empty(),
          enviarLote: (id, p) async => ResultadoLote.recibido,
        ),
        panico: PanicoService(enviar: (id, lat, lng) async {
          enviados.add([lat, lng]);
          return ResultadoPanico.confirmado;
        }),
      );

      expect(await c.pulsarPanico(5), ResultadoPanico.confirmado);
      expect(enviados.single, [10.9, -73.1]);
    });
  });
}
