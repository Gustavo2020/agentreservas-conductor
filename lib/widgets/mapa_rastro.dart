import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../config/theme.dart';
import '../services/estilo_mapa.dart';
import '../services/proveedor_teselas.dart';
import '../services/seguimiento_service.dart';
import 'rastro_painter.dart';

/// Mapa real del recorrido: el mapa base de Viasofia, el rastro y el vehículo en su última
/// posición. Si el estilo no llega (sin red, sin Geogaby) o no se entiende, queda el trazo simple:
/// el mapa es un adorno, nunca un requisito.
class MapaRastro extends StatefulWidget {
  final List<MuestraGps> rastro;
  final Future<EstiloMapa?> Function() cargarEstilo;
  final PedirTesela pedirTesela;

  const MapaRastro({
    super.key,
    required this.rastro,
    required this.cargarEstilo,
    required this.pedirTesela,
  });

  @override
  State<MapaRastro> createState() => _MapaRastroState();
}

class _MapaRastroState extends State<MapaRastro> {
  late final Future<EstiloMapa?> _estilo;
  final _controlador = MapController();
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    _estilo = widget.cargarEstilo().then<EstiloMapa?>((e) => e).catchError(
          (Object _) => null,
        );
  }

  @override
  void didUpdateWidget(MapaRastro anterior) {
    super.didUpdateWidget(anterior);
    // El mapa sigue al vehículo.
    if (_listo && widget.rastro.isNotEmpty) {
      _controlador.move(_ultima(widget.rastro), _controlador.camera.zoom);
    }
  }

  LatLng _ultima(List<MuestraGps> r) => LatLng(r.last.lat, r.last.lng);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EstiloMapa?>(
      future: _estilo,
      builder: (context, estado) {
        final estilo = estado.data;
        if (estilo == null) return RastroSimple(rastro: widget.rastro);
        return _mapa(estilo);
      },
    );
  }

  Widget _mapa(EstiloMapa estilo) {
    final puntos = widget.rastro.map((m) => LatLng(m.lat, m.lng)).toList();
    final centro = puntos.isNotEmpty
        ? puntos.last
        : (estilo.limites?.center ?? const LatLng(11.0, -73.0));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FlutterMap(
        mapController: _controlador,
        options: MapOptions(
          initialCenter: centro,
          initialZoom: 12,
          minZoom: estilo.zoomMinimo.toDouble(),
          maxZoom: 16,
          onMapReady: () => _listo = true,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          VectorTileLayer(
            theme: estilo.tema,
            tileProviders: TileProviders({
              estilo.fuente:
                  ProveedorTeselasConductor(estilo, widget.pedirTesela),
            }),
          ),
          PolylineLayer(polylines: [
            Polyline(points: puntos, strokeWidth: 4, color: AppTheme.primary),
          ]),
          if (puntos.isNotEmpty)
            MarkerLayer(markers: [
              Marker(
                point: puntos.last,
                width: 18,
                height: 18,
                child: Container(
                  key: const Key('vehiculo_en_mapa'),
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Para quien sólo necesita la firma de bytes (p. ej. pruebas).
Future<Uint8List> sinTeselas(String _) async => Uint8List(0);
