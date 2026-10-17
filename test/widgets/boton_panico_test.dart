import 'package:agentreservas_conductor/widgets/boton_panico.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Future<void> Function() onActivar) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: BotonPanico(
            onActivar: onActivar,
            duracion: const Duration(seconds: 2),
          ),
        ),
      ),
    );

void main() {
  testWidgets('mantenerlo presionado el tiempo completo lo activa',
      (tester) async {
    var activado = 0;
    await tester.pumpWidget(_app(() async => activado++));
    final gesto =
        await tester.startGesture(tester.getCenter(find.byType(BotonPanico)));
    // El primer cuadro arranca el reloj de la animacion: se avanza en pasos cortos, como un dedo
    // que se mantiene, y a mitad de camino todavia no se activa.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(activado, 0, reason: 'a mitad de camino aun no');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesto.up();
    await tester.pump();
    expect(activado, 1);
  });

  testWidgets('un toque corto (accidental) no pide ayuda', (tester) async {
    var activado = 0;
    await tester.pumpWidget(_app(() async => activado++));
    await tester.tap(find.byType(BotonPanico));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));
    expect(activado, 0);
  });

  testWidgets('soltar antes de tiempo cancela', (tester) async {
    var activado = 0;
    await tester.pumpWidget(_app(() async => activado++));
    final gesto =
        await tester.startGesture(tester.getCenter(find.byType(BotonPanico)));
    await tester.pump(const Duration(milliseconds: 1500));
    await gesto.up();
    await tester.pump(const Duration(seconds: 3));
    expect(activado, 0);
  });

  testWidgets('dice que hay que mantenerlo presionado', (tester) async {
    await tester.pumpWidget(_app(() async {}));
    expect(find.textContaining('mantén presionado'), findsOneWidget);
  });
}
