import 'dart:async';

import 'package:agentreservas_conductor/services/cola_posiciones.dart';
import 'package:agentreservas_conductor/services/panico_service.dart';
import 'package:agentreservas_conductor/services/seguimiento_controller.dart';
import 'package:agentreservas_conductor/services/seguimiento_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _Memoria implements AlmacenCola {
  String? contenido;
  @override
  Future<String?> leer() async => contenido;
  @override
  Future<void> guardar(String c) async => contenido = c;
}

void main() {
  late StreamController<MuestraGps> flujo;
  late List<List<double>> panicos;
  late LocationPermission permiso;
  late bool gps;
  late MuestraGps? posicion;
  late ResultadoPanico resultado;
  late SeguimientoController controlador;
  late SeguimientoService seguimiento;

  setUp(() {
    flujo = StreamController<MuestraGps>();
    panicos = [];
    permiso = LocationPermission.whileInUse;
    gps = true;
    posicion = null;
    resultado = ResultadoPanico.confirmado;
    seguimiento = SeguimientoService(
      cola: ColaPosiciones(_Memoria()),
      abrirFlujo: () => flujo.stream,
      enviarLote: (id, p) async => ResultadoLote.recibido,
      cadaLote: const Duration(hours: 1),
    );
    controlador = SeguimientoController(
      seguimiento: seguimiento,
      panico: PanicoService(enviar: (id, lat, lng) async {
        panicos.add([id.toDouble(), lat, lng]);
        return resultado;
      }),
      pedirPermiso: () async => permiso,
      gpsEncendido: () async => gps,
      posicionAhora: () async => posicion,
    );
  });

  tearDown(() async {
    await seguimiento.detener();
    // Sin escuchas, `close()` no completa nunca: no se espera.
    unawaited(flujo.close());
  });

  test('con permiso y GPS encendido el seguimiento arranca', () async {
    expect(await controlador.iniciar(7), ArranqueSeguimiento.activo);
    expect(seguimiento.activo, isTrue);
  });

  test('sin permiso se dice y no se sigue', () async {
    for (final p in [
      LocationPermission.denied,
      LocationPermission.deniedForever
    ]) {
      permiso = p;
      expect(await controlador.iniciar(7), ArranqueSeguimiento.sinPermiso);
    }
    expect(seguimiento.activo, isFalse);
  });

  test('con el GPS apagado se dice y no se sigue', () async {
    gps = false;
    expect(await controlador.iniciar(7), ArranqueSeguimiento.sinGps);
    expect(seguimiento.activo, isFalse);
  });

  test('el panico usa la ultima posicion si es reciente (no espera al GPS)',
      () async {
    await controlador.iniciar(7);
    flujo.add(MuestraGps(11.5, -72.9, DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    posicion = MuestraGps(0, 0, DateTime.now()); // no debe usarse
    expect(await controlador.pulsarPanico(7), ResultadoPanico.confirmado);
    expect(panicos.single, [7.0, 11.5, -72.9]);
  });

  test('si la ultima es vieja pide una nueva al telefono', () async {
    await controlador.iniciar(7);
    flujo.add(
        MuestraGps(1, 1, DateTime.now().subtract(const Duration(minutes: 10))));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    posicion = MuestraGps(11.7, -72.8, DateTime.now());
    await controlador.pulsarPanico(7);
    expect(panicos.single, [7.0, 11.7, -72.8]);
  });

  test('sin ninguna posicion no se puede pedir ayuda y se avisa con nulo',
      () async {
    expect(await controlador.pulsarPanico(7), isNull);
    expect(panicos, isEmpty);
  });

  test('un rechazo del servidor llega a la pantalla', () async {
    posicion = MuestraGps(1, 2, DateTime.now());
    resultado = ResultadoPanico.rechazado;
    expect(await controlador.pulsarPanico(7), ResultadoPanico.rechazado);
  });
}
