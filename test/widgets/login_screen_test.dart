import 'package:agentreservas_conductor/providers/auth_provider.dart';
import 'package:agentreservas_conductor/screens/login_screen.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_firma.dart';
import '../helpers/servidor_falso.dart';

Widget _app(AuthProvider auth) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: LoginScreen()),
    );

AuthProvider _provider(Future<http.Response> Function(http.Request) h) {
  FlutterSecureStorage.setMockInitialValues({});
  return AuthProvider(
    AuthService(
      httpClient: MockClient(h),
      storage: const FlutterSecureStorage(),
      firma: FakeFirmaDispositivo(),
    ),
  );
}

void main() {
  testWidgets('explica el segundo factor antes de pedir la verificación',
      (tester) async {
    await tester.pumpWidget(_app(_provider(ServidorFalso().manejar)));

    expect(find.byKey(const Key('texto_segundo_factor')), findsOneWidget);
    expect(find.textContaining('huella'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('muestra el motivo cuando el aparato no está registrado',
      (tester) async {
    final auth = _provider(
      (_) async => respuestaJson({
        'detail':
            'Este aparato no esta registrado para su cuenta. Pida a su administrador restablecerlo.',
      }, 403),
    );
    await tester.pumpWidget(_app(auth));

    await tester.enterText(find.byType(TextFormField).at(0), 'luis@geb.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-larga');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('administrador'), findsOneWidget);
  });
}
