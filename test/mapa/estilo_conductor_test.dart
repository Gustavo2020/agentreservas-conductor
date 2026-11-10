import 'dart:convert';
import 'dart:io';

import 'package:agentreservas_conductor/services/estilo_mapa.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/estilo_conductor.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('lee el estilo que sirve Viasofia: ninguna capa se pierde', () {
    final estilo = EstiloMapa.desde(fixture())!;
    expect(estilo.tema.layers.length, (fixture()['layers'] as List).length);
    expect(estilo.fuente, 'base');
  });

  test('la ruta de teselas es relativa al servidor y trae la fuente elegida',
      () {
    final estilo = EstiloMapa.desde(fixture())!;
    expect(estilo.rutaTeselas,
        '/api/conductor/mapa/teselas/la_guajira/{z}/{x}/{y}');
    expect(estilo.rutaDe(5, 9, 14),
        '/api/conductor/mapa/teselas/la_guajira/5/9/14');
    expect((estilo.zoomMinimo, estilo.zoomMaximo), (0, 14));
    expect(estilo.limites, isNotNull);
  });

  test('sin fuente de teselas (solo fondo) no hay mapa que dibujar', () {
    final soloFondo = {
      'version': 8,
      'sources': <String, dynamic>{},
      'layers': [
        {
          'id': 'fondo',
          'type': 'background',
          'paint': {'background-color': '#e8ebee'}
        },
      ],
    };
    expect(EstiloMapa.desde(soloFondo), isNull);
  });

  test('un estilo malformado no rompe la app: devuelve nulo', () {
    expect(EstiloMapa.desde({'foo': 1}), isNull);
    expect(
        EstiloMapa.desde({
          'sources': {
            'base': {'tiles': <String>[]}
          },
          'layers': []
        }),
        isNull);
  });
}
