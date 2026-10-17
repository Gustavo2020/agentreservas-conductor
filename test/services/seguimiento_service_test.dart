import 'dart:async';

import 'package:agentreservas_conductor/services/cola_posiciones.dart';
import 'package:agentreservas_conductor/services/seguimiento_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memoria implements AlmacenCola {
  String? contenido;
  @override
  Future<String?> leer() async => contenido;
  @override
  Future<void> guardar(String c) async => contenido = c;
}

MuestraGps _m(double lat, int segundos) => MuestraGps(
      lat,
      -72.9,
      DateTime.fromMillisecondsSinceEpoch(1700000000000 + segundos * 1000),
    );

void main() {
  late StreamController<MuestraGps> flujo;
  late List<List<PuntoGps>> enviados;
  late ResultadoLote respuesta;
  late SeguimientoService servicio;
  late ColaPosiciones cola;

  setUp(() {
    flujo = StreamController<MuestraGps>();
    enviados = [];
    respuesta = ResultadoLote.recibido;
    cola = ColaPosiciones(_Memoria());
    servicio = SeguimientoService(
      cola: cola,
      abrirFlujo: () => flujo.stream,
      enviarLote: (id, puntos) async {
        enviados.add(List.of(puntos));
        return respuesta;
      },
      cadaLote: const Duration(hours: 1), // el temporizador no interviene
    );
  });

  tearDown(() async {
    await servicio.detener();
    await flujo.close();
  });

  Future<void> medir(MuestraGps m) async {
    flujo.add(m);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('guarda con su hora de medida y respeta la separacion minima', () async {
    await servicio.iniciar(7);
    await medir(_m(11.0, 0));
    await medir(_m(11.1, 4)); // menos de 10 s: no se guarda
    await medir(_m(11.2, 12));
    expect(cola.proximoLote(10).map((p) => p.lat), [11.0, 11.2]);
    expect(cola.proximoLote(10).first.tMs, 1700000000000);
  });

  test('sin senal la cola conserva todo y al volver se manda en orden',
      () async {
    await servicio.iniciar(7);
    respuesta = ResultadoLote.reintentar;
    await medir(_m(1, 0));
    await medir(_m(2, 20));
    await servicio.vaciarCola();
    expect(cola.longitud, 2); // nada se perdio
    respuesta = ResultadoLote.recibido;
    await servicio.vaciarCola();
    expect(cola.vacia, isTrue);
    expect(enviados.last.map((p) => p.lat), [1.0, 2.0]);
  });

  test('un lote mal formado se omite y no bloquea la cola', () async {
    await servicio.iniciar(7);
    await medir(_m(1, 0));
    respuesta = ResultadoLote.omitir;
    await servicio.vaciarCola();
    expect(cola.vacia, isTrue);
    expect(servicio.activo, isTrue); // se sigue siguiendo el viaje
  });

  test('si el servidor descarta el viaje se vacia la cola y se deja de seguir',
      () async {
    await servicio.iniciar(7);
    await medir(_m(1, 0));
    respuesta = ResultadoLote.descartar;
    await servicio.vaciarCola();
    expect(cola.vacia, isTrue);
    expect(servicio.activo, isFalse);
  });

  test('iniciar dos veces el mismo viaje no abre un segundo flujo', () async {
    await servicio.iniciar(7);
    await servicio.iniciar(7);
    await medir(_m(1, 0));
    expect(cola.longitud, 1);
  });

  test('lo que quedo de una sesion anterior se manda al iniciar', () async {
    final disco = _Memoria();
    final previa = ColaPosiciones(disco);
    await previa.agregar(const PuntoGps(9, 9, 1000));
    final s = SeguimientoService(
      cola: ColaPosiciones(disco),
      abrirFlujo: () => flujo.stream,
      enviarLote: (id, p) async {
        enviados.add(List.of(p));
        return ResultadoLote.recibido;
      },
      cadaLote: const Duration(hours: 1),
    );
    await s.iniciar(7);
    await Future<void>.delayed(Duration.zero);
    expect(enviados.single.single, const PuntoGps(9, 9, 1000));
    await s.detener();
  });

  test('recuerda la ultima posicion conocida para el boton de panico',
      () async {
    await servicio.iniciar(7);
    await medir(_m(11.5, 0));
    expect(servicio.ultimaConocida!.lat, 11.5);
  });

  test('detener cierra el flujo: ya no se guarda nada', () async {
    await servicio.iniciar(7);
    await servicio.detener();
    flujo.add(_m(1, 0));
    await Future<void>.delayed(Duration.zero);
    expect(cola.vacia, isTrue);
  });
}
