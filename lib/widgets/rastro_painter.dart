import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../services/seguimiento_service.dart';

class RastroPainter extends CustomPainter {
  final List<MuestraGps> puntos;
  RastroPainter(this.puntos);

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    var minLat = puntos.first.lat, maxLat = minLat;
    var minLng = puntos.first.lng, maxLng = minLng;
    for (final p in puntos) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    const margen = 8.0;
    final dLat = (maxLat - minLat).abs() < 1e-9 ? 1.0 : maxLat - minLat;
    final dLng = (maxLng - minLng).abs() < 1e-9 ? 1.0 : maxLng - minLng;
    Offset aPantalla(MuestraGps p) => Offset(
          margen + (p.lng - minLng) / dLng * (size.width - 2 * margen),
          size.height -
              margen -
              (p.lat - minLat) / dLat * (size.height - 2 * margen),
        );

    final linea = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final trazo = Path()
      ..moveTo(aPantalla(puntos.first).dx, aPantalla(puntos.first).dy);
    for (final p in puntos.skip(1)) {
      final o = aPantalla(p);
      trazo.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(trazo, linea);
    canvas.drawCircle(
        aPantalla(puntos.last), 6, Paint()..color = AppTheme.success);
  }

  @override
  bool shouldRepaint(RastroPainter old) => old.puntos.length != puntos.length;
}

/// Trazo simple del recorrido (sin mapa): lo que se ve mientras llega el mapa o si no hay mapa.
class RastroSimple extends StatelessWidget {
  final List<MuestraGps> rastro;
  const RastroSimple({super.key, required this.rastro});

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const Key('rastro_alternativo'),
        painter: RastroPainter(rastro),
      );
}
