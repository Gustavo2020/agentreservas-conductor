import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agentreservas_conductor/services/api_service.dart';
import 'package:agentreservas_conductor/services/estilo_mapa.dart';
import 'package:agentreservas_conductor/services/proveedor_teselas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

EstiloMapa estilo() => EstiloMapa.desde(
    jsonDecode(File('test/fixtures/estilo_conductor.json').readAsStringSync())
        as Map<String, dynamic>)!;

void main() {
  test('pide cada tesela a la ruta del conductor por el servicio autenticado',
      () async {
    final pedidas = <String>[];
    final proveedor = ProveedorTeselasConductor(estilo(), (ruta) async {
      pedidas.add(ruta);
      return Uint8List.fromList([1, 2, 3]);
    });
    final bytes = await proveedor.provide(TileIdentity(5, 9, 14));
    expect(bytes, [1, 2, 3]);
    expect(pedidas, ['/api/conductor/mapa/teselas/la_guajira/5/9/14']);
    expect((proveedor.minimumZoom, proveedor.maximumZoom), (0, 14));
  });

  test('una tesela que el servidor no tiene (404) no se reintenta; un 503 si',
      () async {
    ProveedorTeselasConductor con(int codigo) => ProveedorTeselasConductor(
        estilo(), (_) async => throw ApiException(codigo, 'x'));
    final noHay = await con(404)
        .provide(TileIdentity(5, 9, 14))
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(noHay, isA<ProviderException>());
    expect((noHay as ProviderException).retryable, Retryable.none);
    final caido = await con(503)
        .provide(TileIdentity(5, 9, 14))
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect((caido as ProviderException).retryable, Retryable.retry);
  });
}
