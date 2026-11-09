import 'dart:async';

import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:agentreservas_conductor/services/ws_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ignore: close_sinks
class _Sink implements WebSocketSink {
  final enviados = <dynamic>[];
  bool cerrado = false;
  @override
  void add(dynamic data) => enviados.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async =>
      cerrado = true;
  @override
  Future<void> get done async {}
}

class _Canal extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final entrada = StreamController<dynamic>(sync: true);
  // ignore: close_sinks
  final _sink = _Sink();
  @override
  Stream<dynamic> get stream => entrada.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready async {}
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;

  bool get cerrado => _sink.cerrado;
  List<dynamic> get enviados => _sink.enviados;
  void morir() => entrada.close();
  void fallar() => entrada.addError(Exception('rechazado'));
}

void main() {
  late List<_Canal> canales;
  late int verificaciones;

  WsService crear(FakeAsync async,
      {bool resiliente = true, bool canalesFallan = false}) {
    final reloj = async.getClock(DateTime(2026, 1, 1));
    FlutterSecureStorage.setMockInitialValues({'conductor_jwt': 'tok'});
    return WsService(
      AuthService(storage: const FlutterSecureStorage()),
      resiliente: resiliente,
      ahora: reloj.now,
      verificarSesion: () async => verificaciones++,
      crearCanal: (uri) {
        final c = _Canal();
        canales.add(c);
        if (canalesFallan) scheduleMicrotask(c.fallar);
        return c;
      },
    );
  }

  setUp(() {
    canales = [];
    verificaciones = 0;
  });

  test('espera exponencial con tope de 30 s', () {
    const tope = Duration(seconds: 30);
    expect(
      [
        for (var i = 0; i < 6; i++)
          WsService.retrasoExponencial(i, tope).inSeconds
      ],
      [3, 6, 12, 24, 30, 30],
    );
    expect(WsService.retrasoExponencial(40, tope), tope);
  });

  test(
      'resiliente: no se rinde nunca y pregunta por la sesión desde el 2.º fallo',
      () {
    fakeAsync((async) {
      final ws = crear(async, canalesFallan: true);
      unawaited(ws.connect(1));
      async.elapse(const Duration(minutes: 30));
      // Con el límite de 10 intentos de la app de operación se habría detenido antes.
      expect(canales.length, greaterThan(15));
      expect(verificaciones, greaterThanOrEqualTo(1));
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });

  test(
      'app de operación: conserva su reintento de 3 s y no pregunta por la sesión',
      () {
    fakeAsync((async) {
      final ws = crear(async, resiliente: false, canalesFallan: true);
      unawaited(ws.connect(1));
      async.elapse(const Duration(minutes: 1));
      // Igual que antes de la demo: el contador se reinicia al abrir el canal, la espera no crece.
      expect(canales.length, inInclusiveRange(18, 22));
      expect(verificaciones, 0);
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });

  test('reconectarAhora reabre al instante si el canal murió', () {
    fakeAsync((async) {
      final ws = crear(async);
      unawaited(ws.connect(1));
      async.flushMicrotasks();
      expect(canales.length, 1);
      canales.first.morir();
      async.flushMicrotasks();
      // Está esperando el temporizador; la red vuelve y se reconecta sin esperar.
      unawaited(ws.reconectarAhora());
      async.flushMicrotasks();
      expect(canales.length, 2);
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });

  test('reconectarAhora no toca un canal vivo', () {
    fakeAsync((async) {
      final ws = crear(async);
      unawaited(ws.connect(1));
      async.flushMicrotasks();
      unawaited(ws.reconectarAhora());
      async.flushMicrotasks();
      expect(canales.length, 1);
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });

  test('el cierre tardío de un canal descartado no mata al nuevo', () {
    fakeAsync((async) {
      final ws = crear(async);
      unawaited(ws.connect(1));
      async.flushMicrotasks();
      final viejo = canales.first;
      viejo.morir();
      async.flushMicrotasks();
      unawaited(ws.reconectarAhora());
      async.flushMicrotasks();
      final nuevo = canales.last;
      expect(nuevo, isNot(same(viejo)));
      expect(nuevo.cerrado, isFalse);
      expect(ws.isConnected, isTrue);
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });

  test('socket mudo más de 90 s se da por muerto y se reconecta', () {
    fakeAsync((async) {
      final ws = crear(async);
      unawaited(ws.connect(1));
      async.flushMicrotasks();
      expect(canales.length, 1);
      async.elapse(const Duration(minutes: 3));
      expect(canales.length, greaterThanOrEqualTo(2));
      expect(canales.first.cerrado, isTrue);
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });

  test('un canal que recibe mensajes no se reconecta', () {
    fakeAsync((async) {
      final ws = crear(async);
      unawaited(ws.connect(1));
      async.flushMicrotasks();
      for (var i = 0; i < 10; i++) {
        async.elapse(const Duration(seconds: 30));
        canales.first.entrada.add('{"tipo":"PONG"}');
      }
      expect(canales.length, 1);
      unawaited(ws.disconnect());
      async.flushMicrotasks();
    });
  });
}
