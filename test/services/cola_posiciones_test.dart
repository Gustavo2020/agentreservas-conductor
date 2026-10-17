import 'package:agentreservas_conductor/services/cola_posiciones.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memoria implements AlmacenCola {
  String? contenido;
  @override
  Future<String?> leer() async => contenido;
  @override
  Future<void> guardar(String c) async => contenido = c;
}

void main() {
  group('ColaPosiciones', () {
    test('guarda cada punto con su hora de medida y lo recupera tras reiniciar',
        () async {
      final disco = _Memoria();
      final cola = ColaPosiciones(disco);
      await cola.agregar(const PuntoGps(11.5, -72.9, 1000));
      await cola.agregar(const PuntoGps(11.6, -72.8, 2000));

      // La app se reinicia: otra cola sobre el mismo disco ve lo mismo.
      final despues = ColaPosiciones(disco);
      await despues.cargar();
      expect(despues.longitud, 2);
      expect(despues.proximoLote(10).first, const PuntoGps(11.5, -72.9, 1000));
    });

    test('el lote sale del mas viejo y solo se quita al confirmar', () async {
      final cola = ColaPosiciones(_Memoria());
      for (var i = 1; i <= 5; i++) {
        await cola.agregar(PuntoGps(1.0 * i, 2.0, i * 1000));
      }
      final lote = cola.proximoLote(3);
      expect(lote.map((p) => p.tMs), [1000, 2000, 3000]);
      // Sin confirmar (el envio fallo) siguen todos.
      expect(cola.longitud, 5);
      await cola.confirmar(3);
      expect(cola.longitud, 2);
      expect(cola.proximoLote(10).map((p) => p.tMs), [4000, 5000]);
    });

    test('al llenarse descarta lo mas viejo y conserva lo mas reciente',
        () async {
      final cola = ColaPosiciones(_Memoria(), maximo: 3);
      for (var i = 1; i <= 5; i++) {
        await cola.agregar(PuntoGps(0, 0, i));
      }
      expect(cola.proximoLote(10).map((p) => p.tMs), [3, 4, 5]);
    });

    test('un contenido danado se ignora: la cola empieza vacia', () async {
      final disco = _Memoria()..contenido = '{no es una lista';
      final cola = ColaPosiciones(disco);
      await cola.cargar();
      expect(cola.vacia, isTrue);
      // Y sigue funcionando.
      await cola.agregar(const PuntoGps(1, 2, 3));
      expect(cola.longitud, 1);
    });

    test('confirmar mas de lo que hay no rompe', () async {
      final cola = ColaPosiciones(_Memoria());
      await cola.agregar(const PuntoGps(1, 2, 3));
      await cola.confirmar(10);
      expect(cola.vacia, isTrue);
    });

    test('toJson usa la clave t que espera el servidor', () {
      expect(const PuntoGps(11.5, -72.9, 1700000000000).toJson(),
          {'lat': 11.5, 'lng': -72.9, 't': 1700000000000});
    });
  });
}
