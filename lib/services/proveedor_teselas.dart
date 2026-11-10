import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'api_service.dart';
import 'estilo_mapa.dart';

/// Pide una tesela por su ruta (relativa al servidor) con la sesión del conductor.
typedef PedirTesela = Future<Uint8List> Function(String ruta);

/// Teselas del mapa base desde Viasofia, que las reenvía de Geogaby. Cada petición lleva el token
/// vigente (lo pone [PedirTesela], p. ej. `ApiService.getBytes`), no uno fijo al crear el mapa.
class ProveedorTeselasConductor extends VectorTileProvider {
  final EstiloMapa _estilo;
  final PedirTesela _pedir;

  ProveedorTeselasConductor(this._estilo, this._pedir);

  @override
  int get minimumZoom => _estilo.zoomMinimo;

  @override
  int get maximumZoom => _estilo.zoomMaximo;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    try {
      return await _pedir(_estilo.rutaDe(tile.z, tile.x, tile.y));
    } on ApiException catch (e) {
      // 4xx (no hay tesela, sin permiso): reintentar no cambia nada. 5xx: Geogaby puede volver.
      final reintentar = e.statusCode >= 500;
      throw ProviderException(
        message: 'Tesela no disponible (${e.statusCode})',
        statusCode: e.statusCode,
        retryable: reintentar ? Retryable.retry : Retryable.none,
      );
    } on Exception catch (e) {
      throw ProviderException(message: '$e', retryable: Retryable.retry);
    }
  }
}
