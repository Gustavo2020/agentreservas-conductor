import 'package:agentreservas_conductor/config/theme.dart';
import 'package:agentreservas_conductor/widgets/estado_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget w) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: w));

// Sin MaterialApp para no incluir FadeTransitions de routing en el árbol
Widget _wrapSimple(Widget w) => Directionality(
      textDirection: TextDirection.ltr,
      child: w,
    );

void main() {
  group('EstadoBadge — texto por estado', () {
    testWidgets('APROBADO muestra "Próximo"', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'APROBADO')));
      expect(find.text('Próximo'), findsOneWidget);
    });

    testWidgets('EN_CURSO muestra "En curso"', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'EN_CURSO')));
      expect(find.text('En curso'), findsOneWidget);
    });

    testWidgets('PENDIENTE muestra "Pendiente"', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'PENDIENTE')));
      expect(find.text('Pendiente'), findsOneWidget);
    });

    testWidgets('RECHAZADO muestra "Rechazado"', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'RECHAZADO')));
      expect(find.text('Rechazado'), findsOneWidget);
    });

    testWidgets('FINALIZADO muestra "Finalizado"', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'FINALIZADO')));
      expect(find.text('Finalizado'), findsOneWidget);
    });

    testWidgets('estado desconocido muestra el valor tal cual', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'ESTADO_RARO')));
      expect(find.text('ESTADO_RARO'), findsOneWidget);
    });
  });

  group('EstadoBadge — colores', () {
    testWidgets('APROBADO usa color success', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'APROBADO')));
      final text = tester.widget<Text>(find.text('Próximo'));
      expect(text.style?.color, AppTheme.success);
    });

    testWidgets('RECHAZADO usa color error', (tester) async {
      await tester.pumpWidget(_wrap(const EstadoBadge(estado: 'RECHAZADO')));
      final text = tester.widget<Text>(find.text('Rechazado'));
      expect(text.style?.color, AppTheme.error);
    });
  });

  group('EstadoBadge — modo pulsante', () {
    testWidgets('pulsante=false no incluye FadeTransition', (tester) async {
      await tester.pumpWidget(
          _wrapSimple(const EstadoBadge(estado: 'APROBADO', pulsante: false)));
      expect(find.byType(FadeTransition), findsNothing);
    });

    testWidgets('pulsante=true incluye FadeTransition', (tester) async {
      await tester.pumpWidget(
          _wrapSimple(const EstadoBadge(estado: 'EN_CURSO', pulsante: true)));
      await tester.pump();
      expect(find.byType(FadeTransition), findsOneWidget);
    });
  });
}
