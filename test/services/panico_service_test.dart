import 'package:agentreservas_conductor/services/panico_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('si llega al primer intento no queda nada pendiente', () async {
    var llamadas = 0;
    final s = PanicoService(enviar: (id, lat, lng) async {
      llamadas++;
      return ResultadoPanico.confirmado;
    });
    expect(await s.pulsar(7, 11.5, -72.9), ResultadoPanico.confirmado);
    expect(s.pendiente, isFalse);
    expect(llamadas, 1);
  });

  test('sin senal se reintenta solo hasta que el servidor confirma', () {
    fakeAsync((reloj) {
      var intentos = 0;
      final s = PanicoService(
        reintentoCada: const Duration(seconds: 5),
        enviar: (id, lat, lng) async {
          intentos++;
          // Confirma al tercer intento.
          return intentos >= 3
              ? ResultadoPanico.confirmado
              : ResultadoPanico.reintentar;
        },
      );
      s.pulsar(7, 11.5, -72.9);
      reloj.flushMicrotasks();
      expect(intentos, 1);
      expect(s.pendiente, isTrue);
      reloj.elapse(const Duration(seconds: 5));
      expect(intentos, 2);
      reloj.elapse(const Duration(seconds: 5));
      expect(intentos, 3);
      reloj.flushMicrotasks();
      expect(s.pendiente, isFalse);
      // Confirmado: no sigue insistiendo.
      reloj.elapse(const Duration(seconds: 30));
      expect(intentos, 3);
    });
  });

  test('un error al enviar cuenta como no entregado, no rompe', () {
    fakeAsync((reloj) {
      var intentos = 0;
      final s = PanicoService(enviar: (id, lat, lng) async {
        intentos++;
        throw Exception('sin red');
      });
      s.pulsar(7, 1, 2);
      reloj.flushMicrotasks();
      expect(s.pendiente, isTrue);
      reloj.elapse(const Duration(seconds: 10));
      expect(intentos, greaterThan(1));
      s.dispose();
      expect(s.pendiente, isFalse);
    });
  });

  test('pulsar de nuevo reemplaza el reintento anterior (no se acumulan)', () {
    fakeAsync((reloj) {
      var intentos = 0;
      final s = PanicoService(enviar: (id, lat, lng) async {
        intentos++;
        return ResultadoPanico.reintentar;
      });
      s.pulsar(7, 1, 2);
      s.pulsar(7, 1, 2);
      reloj.flushMicrotasks();
      final tras2 = intentos;
      reloj.elapse(const Duration(seconds: 5));
      // Un solo temporizador: un intento por periodo, no dos.
      expect(intentos - tras2, 1);
      s.dispose();
    });
  });

  test('un rechazo definitivo no se reintenta y se informa', () {
    fakeAsync((reloj) {
      var intentos = 0;
      final s = PanicoService(enviar: (id, lat, lng) async {
        intentos++;
        return ResultadoPanico.rechazado;
      });
      ResultadoPanico? r;
      s.pulsar(7, 1, 2).then((x) => r = x);
      reloj.flushMicrotasks();
      expect(r, ResultadoPanico.rechazado);
      expect(s.pendiente, isFalse);
      reloj.elapse(const Duration(seconds: 30));
      expect(intentos, 1);
    });
  });
}
