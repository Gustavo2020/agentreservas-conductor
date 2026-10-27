import 'package:agentreservas_conductor/providers/auth_provider.dart';
import 'package:agentreservas_conductor/providers/ws_provider.dart';
import 'package:agentreservas_conductor/screens/codigo_enlace_screen.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:agentreservas_conductor/services/ws_service.dart';
import 'package:agentreservas_conductor/widgets/banda_demo.dart';
import 'package:agentreservas_conductor/widgets/panel_posicion_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_firma.dart';
import '../helpers/servidor_falso.dart';

AuthProvider _auth(Future<http.Response> Function(http.Request) h) {
  FlutterSecureStorage.setMockInitialValues({});
  return AuthProvider(AuthService(
    httpClient: MockClient(h),
    storage: const FlutterSecureStorage(),
    firma: FakeFirmaDispositivo(),
  ));
}

Widget _enlace(AuthProvider a) => ChangeNotifierProvider<AuthProvider>.value(
      value: a,
      child: const MaterialApp(home: CodigoEnlaceScreen()),
    );

void main() {
  group('CodigoEnlaceScreen', () {
    testWidgets('exige exactamente 6 dígitos antes de llamar al servidor',
        (tester) async {
      var llamadas = 0;
      await tester.pumpWidget(_enlace(_auth((_) async {
        llamadas++;
        return respuestaJson({});
      })));

      await tester.enterText(
          find.byKey(const Key('campo_codigo_enlace')), '123');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text(TextosDemo.codigoIncompleto), findsOneWidget);
      expect(llamadas, 0);
    });

    testWidgets('solo acepta dígitos y máximo 6', (tester) async {
      await tester.pumpWidget(_enlace(_auth((_) async => respuestaJson({}))));
      await tester.enterText(
          find.byKey(const Key('campo_codigo_enlace')), 'a1b2c3d4e5f6g7');
      final campo = tester
          .widget<TextFormField>(find.byKey(const Key('campo_codigo_enlace')));
      expect(campo.controller!.text, '123456');
    });

    testWidgets('código rechazado muestra el motivo', (tester) async {
      await tester.pumpWidget(
          _enlace(_auth((_) async => respuestaJson({'detail': 'x'}, 401))));

      await tester.enterText(
          find.byKey(const Key('campo_codigo_enlace')), '654321');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error_codigo_enlace')), findsOneWidget);
      expect(find.textContaining('Código inválido'), findsOneWidget);
    });
  });

  group('BandaDemo', () {
    testWidgets('activa: muestra «MODO DEMO» sobre la app', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BandaDemo(activa: true, child: Scaffold(body: Text('app'))),
      ));
      expect(find.byKey(const Key('banda_modo_demo')), findsOneWidget);
      expect(find.textContaining('MODO DEMO'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('inactiva (APK normal): no agrega nada', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BandaDemo(activa: false, child: Scaffold(body: Text('app'))),
      ));
      expect(find.byKey(const Key('banda_modo_demo')), findsNothing);
    });
  });

  group('PanelPosicionDemo', () {
    Widget app(WsProvider ws, {bool activa = true}) =>
        ChangeNotifierProvider<WsProvider>.value(
          value: ws,
          child: MaterialApp(
            home: Scaffold(body: PanelPosicionDemo(activa: activa)),
          ),
        );

    testWidgets('muestra la posición que llega del servidor', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final ws = WsProvider(
          WsService(AuthService(storage: const FlutterSecureStorage())));
      await tester.pumpWidget(app(ws));
      expect(find.text(TextosPosicionDemo.esperando), findsOneWidget);
    });

    testWidgets('inactivo (APK normal) no ocupa espacio', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final ws = WsProvider(
          WsService(AuthService(storage: const FlutterSecureStorage())));
      await tester.pumpWidget(app(ws, activa: false));
      expect(find.byKey(const Key('panel_posicion_demo')), findsNothing);
    });
  });
}
