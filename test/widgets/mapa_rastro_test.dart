import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agentreservas_conductor/services/estilo_mapa.dart';
import 'package:agentreservas_conductor/services/seguimiento_service.dart';
import 'package:agentreservas_conductor/widgets/mapa_rastro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

EstiloMapa estilo() => EstiloMapa.desde(
    jsonDecode(File('test/fixtures/estilo_conductor.json').readAsStringSync())
        as Map<String, dynamic>)!;

final ahora = DateTime.utc(2026, 11, 9);
final rastro = [
  MuestraGps(10.77, -73.0, ahora),
  MuestraGps(10.80, -72.95, ahora),
  MuestraGps(10.85, -72.9, ahora),
];

Widget app(MapaRastro mapa) =>
    MaterialApp(home: Scaffold(body: SizedBox(height: 200, child: mapa)));

void main() {
  testWidgets(
      'con estilo dibuja el mapa, el rastro y el vehiculo en su ultima posicion',
      (t) async {
    await t.pumpWidget(app(MapaRastro(
      rastro: rastro,
      cargarEstilo: () async => estilo(),
      pedirTesela: (_) async => Uint8List(0),
    )));
    await t.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    final linea = t.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(linea.polylines.single.points.length, 3);
    expect(linea.polylines.single.points.last.latitude, 10.85);
    expect(find.byKey(const Key('vehiculo_en_mapa')), findsOneWidget);
    expect(find.byKey(const Key('rastro_alternativo')), findsNothing);
    // La capa de teselas deja un temporizador de 3 s: se descarta el arbol y se le da su tiempo.
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'sin estilo (sin red o sin Geogaby) cae al trazo simple, sin error',
      (t) async {
    await t.pumpWidget(app(MapaRastro(
      rastro: rastro,
      cargarEstilo: () async => null,
      pedirTesela: (_) async => Uint8List(0),
    )));
    await t.pump();
    expect(find.byKey(const Key('rastro_alternativo')), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('si pedir el estilo falla tambien cae al trazo simple',
      (t) async {
    await t.pumpWidget(app(MapaRastro(
      rastro: rastro,
      cargarEstilo: () async => throw Exception('sin red'),
      pedirTesela: (_) async => Uint8List(0),
    )));
    await t.pump();
    expect(find.byKey(const Key('rastro_alternativo')), findsOneWidget);
  });

  testWidgets('mientras carga el estilo muestra el trazo simple, no un hueco',
      (t) async {
    await t.pumpWidget(app(MapaRastro(
      rastro: rastro,
      cargarEstilo: () =>
          Future<EstiloMapa?>.delayed(const Duration(seconds: 5)),
      pedirTesela: (_) async => Uint8List(0),
    )));
    expect(find.byKey(const Key('rastro_alternativo')), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });
}
