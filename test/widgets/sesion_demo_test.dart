import 'dart:async';
import 'dart:io';

import 'package:agentreservas_conductor/config/textos_demo_alertas.dart';
import 'package:agentreservas_conductor/providers/auth_provider.dart';
import 'package:agentreservas_conductor/screens/codigo_enlace_screen.dart';
import 'package:agentreservas_conductor/screens/login_screen.dart';
import 'package:agentreservas_conductor/screens/viajes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_demo_prueba.dart';

/// Error 1: en la APK de demostración TODO camino que termina la sesión debe aterrizar en la
/// pantalla del código de enlace, nunca en el login de correo y contraseña de la app de operación.
void main() {
  late AppPrueba app;

  // Al terminar se libera la app y se deja correr el reloj: los temporizadores que quedaran
  // pendientes (vencimiento de 6 h, espera de los permisos) hacen fallar la prueba.
  void prueba(String descripcion, Future<void> Function(WidgetTester) cuerpo) {
    testWidgets(descripcion, (t) async {
      try {
        await cuerpo(t);
      } finally {
        app.dispose();
        await t.pump(const Duration(seconds: 2));
      }
    });
  }

  Future<void> abrir(WidgetTester t) async {
    await t.pumpWidget(app.widget());
    await t.pumpAndSettle();
  }

  void esPantallaDelCodigo() {
    expect(find.byType(CodigoEnlaceScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const Key('campo_codigo_enlace')), findsOneWidget);
    expect(find.text('AgentReservas App Conductor'), findsNothing);
  }

  group('con sesión activa', () {
    prueba('arranca en la lista de viajes', (t) async {
      app = AppPrueba();
      await abrir(t);
      expect(find.byType(ViajesScreen), findsOneWidget);
    });

    prueba('botón «Cerrar sesión» lleva a la pantalla del código', (t) async {
      app = AppPrueba();
      await abrir(t);

      await t.tap(find.byIcon(Icons.logout));
      await t.pumpAndSettle();

      esPantallaDelCodigo();
      // Cerrarla uno mismo no necesita explicación.
      expect(find.byKey(const Key('aviso_sesion_terminada')), findsNothing);
    });

    prueba(
        'tras cerrar el viaje (pila reemplazada) «Cerrar sesión» sigue llevando al código',
        (t) async {
      app = AppPrueba();
      await abrir(t);
      // Como al cerrar el viaje: la pila entera se reemplaza por una lista nueva.
      unawaited(app.navegador.currentState!.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const ViajesScreen(demo: true)),
        (_) => false,
      ));
      await t.pumpAndSettle();
      expect(find.byType(ViajesScreen), findsOneWidget);

      await t.tap(find.byIcon(Icons.logout));
      await t.pumpAndSettle();

      esPantallaDelCodigo();
    });

    prueba('el servidor revoca la sesión (401) en la lista de viajes',
        (t) async {
      app = AppPrueba()..revocado = true;
      await abrir(t);

      esPantallaDelCodigo();
      expect(find.byKey(const Key('aviso_sesion_terminada')), findsOneWidget);
      expect(find.text(TextosSesionDemo.sesionTerminada), findsOneWidget);
    });

    prueba(
        'simulación detenida o código nuevo: un 401 con pantallas y diálogos encima '
        'vuelve al código y vacía la pila', (t) async {
      app = AppPrueba();
      await abrir(t);
      final nav = app.navegador.currentState!;
      unawaited(nav.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detalle')))));
      await t.pumpAndSettle();
      unawaited(nav.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('soportes')))));
      await t.pumpAndSettle();
      unawaited(showDialog<void>(
        context: app.navegador.currentContext!,
        builder: (_) => const AlertDialog(content: Text('un diálogo')),
      ));
      await t.pumpAndSettle();

      app.revocado = true;
      // Cualquier llamada autenticada posterior recibe 401.
      await expectLater(
          app.api.get('/api/conductor/mis-viajes'), throwsA(anything));
      await t.pumpAndSettle();

      esPantallaDelCodigo();
      expect(find.text('un diálogo'), findsNothing);
      expect(find.text('soportes'), findsNothing);
      expect(app.navegador.currentState!.canPop(), isFalse);
      expect(find.text(TextosSesionDemo.sesionTerminada), findsOneWidget);
    });

    prueba('desenlace desde el panel: varios 401 a la vez cierran una sola vez',
        (t) async {
      app = AppPrueba();
      await abrir(t);
      app.revocado = true;
      await Future.wait([
        app.api.get('/a').then((_) {}, onError: (_) {}),
        app.api.get('/b').then((_) {}, onError: (_) {}),
        app.api.get('/c').then((_) {}, onError: (_) {}),
      ]);
      await t.pumpAndSettle();

      esPantallaDelCodigo();
      expect(app.auth.motivoFin, MotivoFinSesion.rechazada);
      expect(app.servicio.paradas, 1);
    });

    prueba('el token vence a las 6 h con la app abierta', (t) async {
      app = AppPrueba();
      await abrir(t);
      expect(find.byType(ViajesScreen), findsOneWidget);

      await t.pump(const Duration(hours: 6, minutes: 1));
      await t.pumpAndSettle();

      esPantallaDelCodigo();
      expect(app.auth.motivoFin, MotivoFinSesion.vencida);
      expect(find.text(TextosSesionDemo.sesionTerminada), findsOneWidget);
    });

    prueba('al volver a la app con el token ya vencido, va al código',
        (t) async {
      app = AppPrueba();
      await abrir(t);
      expect(find.byType(ViajesScreen), findsOneWidget);
      // El teléfono durmió horas: el temporizador no disparó, pero el token ya venció.
      await const FlutterSecureStorage().write(
        key: 'conductor_jwt',
        value: jwtQueVence(DateTime.now().subtract(const Duration(hours: 1))),
      );

      await app.auth.revisarVencimiento();
      await t.pumpAndSettle();

      esPantallaDelCodigo();
      expect(app.auth.motivoFin, MotivoFinSesion.vencida);
    });
  });

  group('sin sesión', () {
    prueba('el arranque va al código, nunca al login de operación', (t) async {
      app = AppPrueba(conSesion: false);
      await abrir(t);
      esPantallaDelCodigo();
    });

    prueba('token guardado ya vencido: va al código con explicación',
        (t) async {
      app = AppPrueba(
          venceEn: DateTime.now().subtract(const Duration(minutes: 5)));
      await abrir(t);
      esPantallaDelCodigo();
      expect(find.byKey(const Key('aviso_sesion_terminada')), findsOneWidget);
    });
  });

  group('el login de operación no existe en la demostración', () {
    prueba('LoginScreen en demo muestra el código de enlace', (t) async {
      app = AppPrueba(conSesion: false);
      await t.pumpWidget(app.widgetCon(const LoginScreen(demo: true)));
      await t.pumpAndSettle();
      expect(find.byType(CodigoEnlaceScreen), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    prueba('la app de operación sigue entrando por el login de correo',
        (t) async {
      app = AppPrueba(demo: false, conSesion: false);
      await abrir(t);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(CodigoEnlaceScreen), findsNothing);
    });

    prueba('la app de operación sigue cerrando sesión hacia el login de correo',
        (t) async {
      app = AppPrueba(demo: false);
      await abrir(t);
      await t.tap(find.byIcon(Icons.logout));
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    test(
        'ningún código de la demo construye LoginScreen salvo la puerta, la '
        'propia pantalla y la salida de la app de operación', () {
      const permitidos = {
        'lib/screens/puerta_sesion.dart',
        'lib/screens/login_screen.dart',
        'lib/screens/viajes_screen.dart',
      };
      final infractores = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final ruta = f.path.replaceAll('\\', '/');
        if (permitidos.contains(ruta)) continue;
        if (RegExp(r'\bLoginScreen\s*\(').hasMatch(f.readAsStringSync())) {
          infractores.add(ruta);
        }
      }
      expect(infractores, isEmpty);
    });
  });
}
