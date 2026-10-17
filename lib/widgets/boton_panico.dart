import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';

/// Botón de pánico: se MANTIENE PRESIONADO unos segundos para activarlo. Un toque accidental (el
/// teléfono en el bolsillo, un roce) no debe pedir ayuda a operaciones, pero tampoco hay un
/// diálogo de confirmación: en una emergencia no hay tiempo para leer «¿está seguro?».
class BotonPanico extends StatefulWidget {
  /// Lo que se hace al completar la pulsación larga.
  final Future<void> Function() onActivar;

  /// Cuánto hay que mantenerlo presionado.
  final Duration duracion;

  const BotonPanico({
    super.key,
    required this.onActivar,
    this.duracion = const Duration(seconds: 2),
  });

  @override
  State<BotonPanico> createState() => _BotonPanicoState();
}

class _BotonPanicoState extends State<BotonPanico>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progreso =
      AnimationController(vsync: this, duration: widget.duracion);
  bool _activando = false;

  @override
  void initState() {
    super.initState();
    _progreso.addStatusListener((s) async {
      if (s == AnimationStatus.completed && !_activando) {
        _activando = true;
        // Una vibración fuerte confirma, sin mirar la pantalla, que se activó.
        unawaited(HapticFeedback.heavyImpact());
        try {
          await widget.onActivar();
        } finally {
          if (mounted) {
            _activando = false;
            _progreso.reset();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _progreso.dispose();
    super.dispose();
  }

  void _soltar() {
    // Soltar antes de tiempo cancela: vuelve a cero y no pide nada.
    if (_progreso.status != AnimationStatus.completed) _progreso.reset();
  }

  @override
  Widget build(BuildContext context) {
    // `Listener` (eventos crudos del dedo) y no `GestureDetector`: este ultimo espera a decidir si
    // es un toque, un arrastre o una pulsacion larga, y en una emergencia el conteo debe empezar en
    // el instante en que el dedo toca, no cien milisegundos despues.
    return Listener(
      onPointerDown: (_) => _progreso.forward(),
      onPointerUp: (_) => _soltar(),
      onPointerCancel: (_) => _soltar(),
      child: Semantics(
        button: true,
        label: 'Botón de pánico. Mantén presionado para pedir ayuda.',
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.15),
            border: Border.all(color: AppTheme.error, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // El avance de la pulsación: se llena de izquierda a derecha.
              AnimatedBuilder(
                animation: _progreso,
                builder: (_, __) => FractionallySizedBox(
                  widthFactor: _progreso.value,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppTheme.error, size: 30),
                    SizedBox(width: 10),
                    Text(
                      'PÁNICO · mantén presionado',
                      style: TextStyle(
                        color: AppTheme.error,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
