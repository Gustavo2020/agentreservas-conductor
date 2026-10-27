import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../providers/ws_provider.dart';
import '../services/seguimiento_service.dart';

/// Textos del panel de posición de la demo (centralizados para aprobación).
class TextosPosicionDemo {
  TextosPosicionDemo._();

  static const String titulo = 'Posición del vehículo (simulada)';
  static const String esperando = 'Esperando la posición del servidor…';
}

/// En la APK de demostración muestra la posición del vehículo que manda el servidor y el rastro
/// recorrido. En la APK normal no ocupa espacio.
class PanelPosicionDemo extends StatelessWidget {
  final bool? activa;
  const PanelPosicionDemo({super.key, this.activa});

  @override
  Widget build(BuildContext context) {
    if (!(activa ?? AppConfig.modoDemo)) return const SizedBox.shrink();
    final ws = context.watch<WsProvider>();
    final pos = ws.posicionVehiculo;
    return Container(
      key: const Key('panel_posicion_demo'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            TextosPosicionDemo.titulo,
            style: TextStyle(color: AppTheme.onSurface, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            pos == null
                ? TextosPosicionDemo.esperando
                : '${pos.lat.toStringAsFixed(5)}, ${pos.lng.toStringAsFixed(5)}',
            key: const Key('texto_posicion_demo'),
            style: const TextStyle(
              color: AppTheme.onBackground,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(painter: _RastroPainter(ws.rastro)),
          ),
        ],
      ),
    );
  }
}

class _RastroPainter extends CustomPainter {
  final List<MuestraGps> puntos;
  _RastroPainter(this.puntos);

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
  bool shouldRepaint(_RastroPainter old) => old.puntos.length != puntos.length;
}
