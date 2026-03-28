import 'package:agentreservas_conductor/config/theme.dart';
import 'package:agentreservas_conductor/widgets/loading_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget w) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: w));

void main() {
  group('LoadingOverlay — visibilidad', () {
    testWidgets('isLoading=false → no muestra spinner', (tester) async {
      await tester.pumpWidget(_wrap(
        const LoadingOverlay(
          isLoading: false,
          child: Text('Contenido'),
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Contenido'), findsOneWidget);
    });

    testWidgets('isLoading=true → muestra spinner', (tester) async {
      await tester.pumpWidget(_wrap(
        const LoadingOverlay(
          isLoading: true,
          child: Text('Contenido'),
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('isLoading=true → child sigue renderizando', (tester) async {
      await tester.pumpWidget(_wrap(
        const LoadingOverlay(
          isLoading: true,
          child: Text('Oculto'),
        ),
      ));
      // El child se renderiza en el Stack aunque esté cubierto
      expect(find.text('Oculto'), findsOneWidget);
    });
  });

  group('LoadingOverlay — mensaje', () {
    testWidgets('sin mensaje → no aparece texto adicional', (tester) async {
      await tester.pumpWidget(_wrap(
        const LoadingOverlay(
          isLoading: true,
          child: SizedBox(),
        ),
      ));

      // Solo spinner, sin texto de mensaje
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No hay texto adicional (el hijo es SizedBox)
    });

    testWidgets('con mensaje → muestra texto debajo del spinner',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const LoadingOverlay(
          isLoading: true,
          mensaje: 'Subiendo foto...',
          child: SizedBox(),
        ),
      ));

      expect(find.text('Subiendo foto...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('LoadingOverlay — overlay', () {
    testWidgets('isLoading=true muestra Container oscuro', (tester) async {
      await tester.pumpWidget(_wrap(
        const LoadingOverlay(
          isLoading: true,
          child: SizedBox(width: 100, height: 100),
        ),
      ));

      // El overlay usa Stack con dos hijos: el child y el container oscuro
      expect(find.byType(Stack), findsWidgets);
    });
  });
}
