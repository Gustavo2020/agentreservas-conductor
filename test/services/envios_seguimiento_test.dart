import 'package:agentreservas_conductor/services/envios_seguimiento.dart';
import 'package:agentreservas_conductor/services/panico_service.dart';
import 'package:agentreservas_conductor/services/seguimiento_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resultadoDeLote', () {
    test('exito = recibido', () {
      expect(resultadoDeLote(null), ResultadoLote.recibido);
    });
    test('422 (lote mal formado) se omite para no bloquear la cola', () {
      expect(resultadoDeLote(422), ResultadoLote.omitir);
    });
    test('el viaje ya no es de este conductor o no esta en curso: descartar',
        () {
      for (final e in [403, 404, 409]) {
        expect(resultadoDeLote(e), ResultadoLote.descartar, reason: '$e');
      }
    });
    test('401, 5xx y sin red se reintentan', () {
      for (final e in [401, 500, 502, 503, 0]) {
        expect(resultadoDeLote(e), ResultadoLote.reintentar, reason: '$e');
      }
    });
  });

  group('resultadoDePanico', () {
    test('exito = confirmado', () {
      expect(resultadoDePanico(null), ResultadoPanico.confirmado);
    });
    test('un rechazo definitivo no se reintenta', () {
      for (final e in [403, 404, 409, 422]) {
        expect(resultadoDePanico(e), ResultadoPanico.rechazado, reason: '$e');
      }
    });
    test('401, 5xx y sin red se reintentan: pedir ayuda no se rinde', () {
      for (final e in [401, 500, 503, 0]) {
        expect(resultadoDePanico(e), ResultadoPanico.reintentar, reason: '$e');
      }
    });
  });
}
