import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../screens/codigo_enlace_screen.dart';

/// Franja fija «MODO DEMO» en la parte superior de toda la app. Solo aparece en la APK de
/// demostración ([AppConfig.modoDemo]); en la APK normal devuelve [child] sin cambios.
class BandaDemo extends StatelessWidget {
  final Widget child;
  final bool? activa;
  const BandaDemo({super.key, required this.child, this.activa});

  @override
  Widget build(BuildContext context) {
    if (!(activa ?? AppConfig.modoDemo)) return child;
    final media = MediaQuery.of(context);
    return Column(
      children: [
        Material(
          color: const Color(0xFFE65100),
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, media.padding.top + 2, 8, 2),
            child: const SizedBox(
              width: double.infinity,
              child: Text(
                TextosDemo.bandaDetalle,
                key: Key('banda_modo_demo'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
