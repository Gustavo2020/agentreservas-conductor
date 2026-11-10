import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../providers/ws_provider.dart';
import '../services/api_service.dart';
import '../services/estilo_mapa.dart';
import 'mapa_rastro.dart';
import 'rastro_painter.dart';

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
            height: 200,
            width: double.infinity,
            child: _recorrido(context, ws),
          ),
        ],
      ),
    );
  }

  /// El mapa real si la app tiene su servicio de API; si no, el trazo simple.
  Widget _recorrido(BuildContext context, WsProvider ws) {
    ApiService api;
    try {
      api = Provider.of<ApiService>(context, listen: false);
    } on ProviderNotFoundException {
      return RastroSimple(rastro: ws.rastro);
    }
    return MapaRastro(
      key: const Key('mapa_rastro_demo'),
      rastro: ws.rastro,
      cargarEstilo: () async =>
          EstiloMapa.desde(await api.get('/api/conductor/mapa/estilo')),
      pedirTesela: api.getBytes,
    );
  }
}
