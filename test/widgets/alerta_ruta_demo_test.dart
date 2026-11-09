import 'dart:async';

import 'package:agentreservas_conductor/config/textos_demo_alertas.dart';
import 'package:agentreservas_conductor/models/alerta_ruta.dart';
import 'package:agentreservas_conductor/screens/viaje_activo_screen.dart';
import 'package:agentreservas_conductor/screens/viajes_screen.dart';
import 'package:agentreservas_conductor/widgets/dialogo_alerta_ruta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_demo_prueba.dart';

/// Error 2: la alerta de ruta prohibida debe verse al instante, en cualquier pantalla, con
/// notificación del sistema, sin duplicarse, y el socket debe seguir vivo con la app minimizada.
void main() {
  late AppPrueba app;
  var ahoraSim = DateTime(2026, 1, 1, 10);

  void prueba(String descripcion, Future<void> Function(WidgetTester) cuerpo) {
    testWidgets(descripcion, (t) async {
      ahoraSim = DateTime(2026, 1, 1, 10);
      try {
        await cuerpo(t);
      } finally {
        app.dispose();
        await t.pump(const Duration(seconds: 2));
      }
    });
  }

  /// Abre la app con sesión y la deja conectada a un viaje.
  Future<void> abrirConViaje(WidgetTester t, {AppPrueba? propia}) async {
    app = propia ?? AppPrueba(ahora: () => ahoraSim);
    await app.iniciar();
    await t.pumpWidget(app.widget());
    await t.pumpAndSettle();
    await app.wsProvider.conectar(1);
    await t.pump();
  }

  Future<void> llega(WidgetTester t, Map<String, dynamic> m) async {
    app.ws.emitir(m);
    await t.pump();
    await t.pump();
  }

  final dialogo = find.byKey(const Key('alerta_tramo_prohibido'));

  group('aviso inmediato', () {
    prueba('al llegar TRAMO_PROHIBIDO se ve el aviso y sale la notificación',
        (t) async {
      await abrirConViaje(t);
      expect(find.byType(ViajesScreen), findsOneWidget);

      await llega(t, mensajeTramo());

      expect(dialogo, findsOneWidget);
      expect(find.text(TextosViaje.tituloTramoProhibido), findsOneWidget);
      expect(find.text(TextosViaje.entendido), findsOneWidget);
      expect(find.textContaining('Vía Maicao'), findsOneWidget);
      expect(app.notificador.mostradas, hasLength(1));
      expect(app.notificador.mostradas.single.alternativa, 'Vía Maicao');
    });

    prueba('se ve sobre cualquier pantalla abierta, no solo la del viaje',
        (t) async {
      await abrirConViaje(t);
      unawaited(app.navegador.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('soportes')))));
      await t.pumpAndSettle();

      await llega(t, mensajeTramo());

      expect(dialogo, findsOneWidget);
      expect(find.text('soportes'), findsOneWidget);
    });

    prueba('«Entendido» cierra el aviso y retira la notificación', (t) async {
      await abrirConViaje(t);
      await llega(t, mensajeTramo());
      final antes = app.notificador.cancelaciones;

      await t.tap(find.text(TextosViaje.entendido));
      await t.pumpAndSettle();

      expect(dialogo, findsNothing);
      expect(app.notificador.cancelaciones, greaterThan(antes));
    });

    prueba('en la pantalla del viaje el aviso sale una sola vez', (t) async {
      await abrirConViaje(t);
      unawaited(app.navegador.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const ViajeActivoScreen(solicitudId: 1))));
      await t.pumpAndSettle();

      await llega(t, mensajeTramo());
      await t.pumpAndSettle();

      expect(dialogo, findsOneWidget);
      expect(app.notificador.mostradas, hasLength(1));
    });
  });

  group('sin duplicados (idempotencia)', () {
    prueba(
        'el servidor reenvía el mismo aviso: una sola notificación y un diálogo',
        (t) async {
      await abrirConViaje(t);
      await llega(t, mensajeTramo());
      await t.tap(find.text(TextosViaje.entendido));
      await t.pumpAndSettle();

      await llega(t, mensajeTramo());

      expect(dialogo, findsNothing);
      expect(app.notificador.mostradas, hasLength(1));
    });

    prueba('ráfaga de reenvíos mientras el aviso está abierto', (t) async {
      await abrirConViaje(t);
      for (var i = 0; i < 4; i++) {
        await llega(t, mensajeTramo());
      }
      expect(dialogo, findsOneWidget);
      expect(app.notificador.mostradas, hasLength(1));
    });

    prueba('con alerta_id del servidor: mismo id no se repite, otro id sí',
        (t) async {
      await abrirConViaje(t);
      await llega(t, mensajeTramo(alertaId: 41));
      await t.tap(find.text(TextosViaje.entendido));
      await t.pumpAndSettle();

      // Pasa mucho tiempo y el servidor reenvía la misma alerta: sigue siendo la misma.
      ahoraSim = ahoraSim.add(const Duration(hours: 3));
      await llega(t, mensajeTramo(alertaId: 41));
      expect(app.notificador.mostradas, hasLength(1));

      await llega(t, mensajeTramo(alertaId: 42));
      expect(app.notificador.mostradas, hasLength(2));
      expect(dialogo, findsOneWidget);
    });

    prueba('sin id: pasada la ventana, el mismo texto es una alerta nueva',
        (t) async {
      await abrirConViaje(t);
      await llega(t, mensajeTramo());
      await t.tap(find.text(TextosViaje.entendido));
      await t.pumpAndSettle();

      ahoraSim = ahoraSim.add(const Duration(minutes: 11));
      await llega(t, mensajeTramo());

      expect(app.notificador.mostradas, hasLength(2));
      expect(dialogo, findsOneWidget);
    });
  });

  group('abrir desde la notificación', () {
    prueba('tocarla muestra el aviso', (t) async {
      await abrirConViaje(t);
      await llega(t, mensajeTramo());
      await t.tap(find.text(TextosViaje.entendido));
      await t.pumpAndSettle();

      app.notificador.tocar(app.notificador.mostradas.single);
      await t.pumpAndSettle();

      expect(dialogo, findsOneWidget);
    });

    prueba('tocarla con el mismo aviso ya en pantalla no lo duplica',
        (t) async {
      await abrirConViaje(t);
      await llega(t, mensajeTramo());

      app.notificador.tocar(app.notificador.mostradas.single);
      await t.pumpAndSettle();

      expect(dialogo, findsOneWidget);
    });

    prueba(
        'app cerrada: la notificación que la abrió muestra el aviso al iniciar',
        (t) async {
      app = AppPrueba(ahora: () => ahoraSim);
      app.notificador.lanzamiento = const AlertaRuta(
        id: 'x',
        mensaje: 'Entraste a un tramo prohibido. Ruta permitida: Vía Maicao',
        alternativa: 'Vía Maicao',
      );
      await app.iniciar();
      await t.pumpWidget(app.widget());
      await t.pumpAndSettle();

      expect(dialogo, findsOneWidget);
    });

    test('la carga de la notificación sobrevive el viaje de ida y vuelta', () {
      const a = AlertaRuta(
        id: '1|Tramo|msg',
        idDelServidor: true,
        solicitudId: 1,
        mensaje: 'msg',
        alternativa: 'Vía Maicao',
        tramo: 'Tramo',
      );
      final b = AlertaRuta.dePayload(a.toPayload())!;
      expect([b.id, b.idDelServidor, b.solicitudId, b.mensaje, b.alternativa],
          [a.id, true, 1, 'msg', 'Vía Maicao']);
      expect(AlertaRuta.dePayload('no es json'), isNull);
      expect(AlertaRuta.dePayload(null), isNull);
    });
  });

  group('socket vivo mientras hay viaje (servicio en primer plano)', () {
    prueba('al conectar el viaje arranca el servicio; al terminar se apaga',
        (t) async {
      await abrirConViaje(t);
      expect(app.servicio.inicios, 1);

      await llega(t, {'tipo': 'VIAJE_FINALIZADO'});
      await t.pumpAndSettle();

      expect(app.servicio.paradas, greaterThanOrEqualTo(1));
      expect(app.ws.desconexiones, greaterThanOrEqualTo(1));
    });

    prueba(
        'si Android no deja arrancarlo en segundo plano, reintenta al volver',
        (t) async {
      app = AppPrueba(ahora: () => ahoraSim);
      app.servicio.permiteArrancar = false;
      await abrirConViaje(t, propia: app);
      expect(app.servicio.inicios, 1);
      expect(app.gestor!.servicioActivo, isFalse);

      app.servicio.permiteArrancar = true;
      app.gestor!.sincronizar();
      await t.pump();

      expect(app.servicio.inicios, 2);
      expect(app.gestor!.servicioActivo, isTrue);
    });

    prueba('salir de la pantalla del viaje no corta el socket en la demo',
        (t) async {
      await abrirConViaje(t);
      unawaited(app.navegador.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const ViajeActivoScreen(solicitudId: 1))));
      await t.pumpAndSettle();

      app.navegador.currentState!.pop();
      await t.pumpAndSettle();

      // Solo el `conectar` de la prueba y el de la pantalla; nadie desconectó.
      expect(app.ws.desconexiones, 0);
      expect(app.servicio.paradas, 0);
    });

    prueba('al cerrar sesión se apaga el servicio, el socket y la notificación',
        (t) async {
      await abrirConViaje(t);
      await t.tap(find.byIcon(Icons.logout));
      await t.pumpAndSettle();

      expect(app.servicio.paradas, greaterThanOrEqualTo(1));
      expect(app.ws.desconexiones, greaterThanOrEqualTo(1));
      expect(app.notificador.cancelaciones, greaterThanOrEqualTo(1));
      expect(app.wsProvider.solicitudActiva, isNull);
    });
  });

  group('permisos', () {
    prueba('Android 13+: explica y pide el permiso de notificaciones',
        (t) async {
      app = AppPrueba(ahora: () => ahoraSim);
      app.notificador.permiso = false;
      await app.iniciar();
      await t.pumpWidget(app.widget());
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();

      expect(find.text(TextosAlertaRuta.permisoTitulo), findsOneWidget);
      expect(find.text(TextosAlertaRuta.permisoExplicacion), findsOneWidget);
      await t.tap(find.text(TextosAlertaRuta.permisoContinuar));
      await t.pumpAndSettle();

      expect(app.notificador.pedidosDePermiso, 1);
    });

    prueba('«Ahora no» no pide nada; la batería se ofrece una sola vez',
        (t) async {
      app = AppPrueba(ahora: () => ahoraSim);
      app.notificador.permiso = false;
      app.servicio.bateriaLibre = false;
      await app.iniciar();
      await t.pumpWidget(app.widget());
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();

      await t.tap(find.text(TextosAlertaRuta.permisoAhoraNo));
      await t.pumpAndSettle();
      expect(app.notificador.pedidosDePermiso, 0);

      expect(find.text(TextosAlertaRuta.bateriaTitulo), findsOneWidget);
      await t.tap(find.text(TextosAlertaRuta.bateriaPermitir));
      await t.pumpAndSettle();
      expect(app.servicio.pedidosDeBateria, 1);
    });

    prueba('con el permiso ya concedido no pregunta nada', (t) async {
      app = AppPrueba(ahora: () => ahoraSim);
      await app.iniciar();
      await t.pumpWidget(app.widget());
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('dialogo_permiso')), findsNothing);
      expect(app.notificador.pedidosDePermiso, 0);
    });
  });

  group('app de operación', () {
    prueba('no tiene gestor: la pantalla del viaje atiende el aviso como antes',
        (t) async {
      app = AppPrueba(demo: false);
      await t.pumpWidget(app.widget());
      await t.pumpAndSettle();
      expect(app.gestor, isNull);
    });
  });
}
