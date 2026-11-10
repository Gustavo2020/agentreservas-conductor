import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// El estilo del mapa base que sirve Viasofia (`GET /api/conductor/mapa/estilo`): las capas ya
/// leídas para dibujar y de dónde pedir las teselas (ruta relativa al servidor, con el token del
/// conductor). Sin fuente de teselas (solo fondo) no hay mapa: [desde] devuelve nulo.
class EstiloMapa {
  final vtr.Theme tema;

  /// Nombre de la fuente en el estilo (une el tema con el proveedor de teselas).
  final String fuente;
  final String rutaTeselas;
  final int zoomMinimo;
  final int zoomMaximo;
  final LatLngBounds? limites;

  const EstiloMapa._(this.tema, this.fuente, this.rutaTeselas, this.zoomMinimo,
      this.zoomMaximo, this.limites);

  /// La ruta de una tesela concreta.
  String rutaDe(int z, int x, int y) => rutaTeselas
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  static EstiloMapa? desde(Map<String, dynamic> json) {
    try {
      final fuentes = json['sources'];
      if (fuentes is! Map || fuentes.isEmpty) return null;
      final nombre = fuentes.keys.first as String;
      final origen = fuentes[nombre] as Map;
      final teselas = origen['tiles'];
      if (teselas is! List || teselas.isEmpty) return null;
      final tema = vtr.ThemeReader().read(json);
      return EstiloMapa._(
        tema,
        nombre,
        teselas.first as String,
        (origen['minzoom'] as num?)?.toInt() ?? 0,
        (origen['maxzoom'] as num?)?.toInt() ?? 14,
        _limites(origen['bounds']),
      );
    } on Object {
      // Un estilo que no se entiende no debe tumbar la pantalla: el llamador usa el trazo simple.
      return null;
    }
  }

  static LatLngBounds? _limites(Object? b) {
    if (b is! List || b.length != 4) return null;
    final v = b.map((e) => (e as num).toDouble()).toList();
    return LatLngBounds(LatLng(v[1], v[0]), LatLng(v[3], v[2]));
  }
}
