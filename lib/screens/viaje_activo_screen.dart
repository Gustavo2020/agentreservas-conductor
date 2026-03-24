import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../config/theme.dart';
import '../providers/viaje_provider.dart';
import '../providers/ws_provider.dart';
import '../services/api_service.dart';
import '../widgets/loading_overlay.dart';
import 'soportes_screen.dart';
import 'cierre_dia_screen.dart';

class ViajeActivoScreen extends StatefulWidget {
  final int solicitudId;
  const ViajeActivoScreen({super.key, required this.solicitudId});

  @override
  State<ViajeActivoScreen> createState() => _ViajeActivoScreenState();
}

class _ViajeActivoScreenState extends State<ViajeActivoScreen> {
  Timer? _gpsTimer;
  Timer? _chequeoAutoTimer;
  bool _procesando = false;
  int _diaActual = 1;

  @override
  void initState() {
    super.initState();
    _conectarWs();
  }

  Future<void> _conectarWs() async {
    final wsProv = context.read<WsProvider>();
    await wsProv.conectar(widget.solicitudId);

    // Escuchar solicitudes de chequeo
    wsProv.addListener(_onWsChange);

    // Recuperar estado del viaje desde la API (cubre hot restart y navegación de vuelta)
    await _recuperarEstadoDesdeApi();
  }

  Future<void> _recuperarEstadoDesdeApi() async {
    final vProv = context.read<ViajeProvider>();
    await vProv.cargarDetalleViaje(widget.solicitudId);
    if (!mounted) return;
    final viaje = vProv.viajeActual;
    if (viaje == null) return;

    // Si el viaje ya está FINALIZADO (por el solicitante o el conductor)
    // mostrar pantalla de cierre y no permitir más acciones.
    if (viaje.estado == 'FINALIZADO') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mostrarViajeTerminado();
      });
      return;
    }

    // Actualizar el día activo desde los cierres registrados en la API.
    setState(() => _diaActual = viaje.diaActual);

    final wsProv = context.read<WsProvider>();
    // Si todos los días ya fueron cerrados, pasar a esperar finalización.
    if (viaje.todosLosDiasCerrados) {
      wsProv.marcarEsperandoFinalizacion();
    } else {
      // Usar eventos de trazabilidad (viajeIniciado / enSitio), NO esEnCurso:
      // el backend pone EN_CURSO al asignar el vehículo, antes de que el
      // conductor realmente arranque. Esto causaba que la pantalla saltara
      // directamente a enRuta sin pasar por el flujo de abordaje.
      wsProv.recuperarEstadoDeViaje(
        viajeIniciado: viaje.viajeIniciado,
        enSitio: viaje.enSitio,
      );
    }
  }

  void _mostrarViajeTerminado() {
    if (!mounted) return;
    context.read<WsProvider>().limpiarViajeTerminado();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Viaje finalizado'),
        content: const Text(
            'El solicitante ha aprobado la liquidación y cerrado el viaje. '
            'Gracias por tu trabajo.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<ViajeProvider>().cargarMisViajes();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirCierreDia() async {
    final cerrado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CierreDiaScreen(
          solicitudId: widget.solicitudId,
          diaNumero: _diaActual,
        ),
      ),
    );
    // Si el día fue cerrado exitosamente, recargar el estado para que
    // _diaActual avance al siguiente día según los cierres en la API.
    if (cerrado == true && mounted) {
      await _recuperarEstadoDesdeApi();
    }
  }

  void _onWsChange() {
    final wsProv = context.read<WsProvider>();
    if (wsProv.viajeTerminado && mounted) {
      _mostrarViajeTerminado();
      return;
    }
    if (wsProv.solicitudCancelada && mounted) {
      _mostrarAlertaCancelacion(wsProv.mensajeCancelacion ?? 'El viaje ha sido cancelado.');
      wsProv.limpiarCancelacion();
      return;
    }
    if (wsProv.viajeConfirmadoPorSolicitante && mounted) {
      wsProv.limpiarViajeConfirmado();
      // Diferir al siguiente frame para no llamar setState durante notifyListeners()
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _iniciarViaje();
      });
      return;
    }
    if (wsProv.chequeoSolicitado && mounted) {
      _mostrarBottomSheetChequeo();
    }
    if (wsProv.enModoPanico) {
      _iniciarGpsParanico();
    } else {
      _detenerGpsPanico();
    }
  }

  void _mostrarAlertaCancelacion(String mensaje) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Viaje cancelado'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Volver a la lista de viajes
              context.read<ViajeProvider>().cargarMisViajes();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  // ── GPS modo pánico ────────────────────────────────────────────────────────

  void _iniciarGpsParanico() {
    if (_gpsTimer != null) return;
    _gpsTimer =
        Timer.periodic(AppConfig.gpsPanicoInterval, (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        if (mounted) {
          context.read<WsProvider>().sendGps(pos.latitude, pos.longitude);
        }
      } catch (_) {}
    });
  }

  void _detenerGpsPanico() {
    _gpsTimer?.cancel();
    _gpsTimer = null;
  }

  // ── Chequeo horario ────────────────────────────────────────────────────────

  void _mostrarBottomSheetChequeo() {
    _chequeoAutoTimer?.cancel();
    // Auto-reportar ANORMAL si no responde en 60 minutos
    _chequeoAutoTimer =
        Timer(AppConfig.chequeoTimeout, () => _responderChequeo('ANORMAL'));

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ChequeoBottomSheet(
        onRespuesta: _responderChequeo,
      ),
    );
  }

  Future<void> _responderChequeo(String estado) async {
    _chequeoAutoTimer?.cancel();
    Navigator.of(context, rootNavigator: true).popUntil(
        (r) => r.isFirst || !r.settings.name!.startsWith('chequeo'));

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      await context.read<ApiService>().registrarChequeo(
        widget.solicitudId,
        estado: estado,
        lat: pos.latitude,
        lng: pos.longitude,
        diaNumero: _diaActual,
      );
    } catch (_) {}

    if (!mounted) return;
    final wsProv = context.read<WsProvider>();
    wsProv.resolverChequeo();
    if (estado == 'ANORMAL') {
      wsProv.activarModoPanico();
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<void> _reportarEnSitio() async {
    // El checklist preoperacional debe haber sido APROBADO antes de reportar en sitio
    final viaje = context.read<ViajeProvider>().viajeActual;
    if (viaje?.checklist == null || !viaje!.checklist!.aprobado) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El checklist preoperacional debe estar aprobado por el responsable antes de iniciar.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    setState(() => _procesando = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final ok = await context.read<ViajeProvider>().reportarEnSitio(
            widget.solicitudId,
            lat: pos.latitude,
            lng: pos.longitude,
          );
      if (ok && mounted) {
        context.read<WsProvider>().marcarEnSitio();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo obtener GPS: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _iniciarViaje() async {
    setState(() => _procesando = true);
    final ok = await context
        .read<ViajeProvider>()
        .iniciarViaje(widget.solicitudId);
    if (mounted) {
      setState(() => _procesando = false);
      if (ok) context.read<WsProvider>().marcarViajeIniciado();
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _chequeoAutoTimer?.cancel();
    context.read<WsProvider>()
      ..removeListener(_onWsChange)
      ..desconectar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wsProv = context.watch<WsProvider>();
    final vProv = context.watch<ViajeProvider>();
    final viaje = vProv.viajeActual;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(viaje?.token ?? 'Viaje activo'),
            Text(
              'Día $_diaActual',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurface,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: LoadingOverlay(
        isLoading: _procesando,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildEstado(wsProv.estado, viaje?.solicitanteNombre),
        ),
      ),
    );
  }

  Widget _buildEstado(EstadoViajeActivo estado, String? solicitante) {
    return switch (estado) {
      EstadoViajeActivo.esperandoInicio => _PanelAccion(
          icon: Icons.place,
          titulo: 'En el sitio de recogida',
          descripcion: 'Presiona cuando estés en el punto de encuentro',
          colorBoton: AppTheme.primary,
          textoBoton: '📍 Estoy en el sitio de recogida',
          onPressed: _reportarEnSitio,
        ),
      EstadoViajeActivo.esperandoConfirmacionUsuario => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 24),
              Text(
                'Esperando que ${solicitante ?? "el solicitante"} confirme el abordaje...',
                style: const TextStyle(
                    color: AppTheme.onBackground, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      // viajeConfirmado ya no se alcanza: el WS trigger auto-llama _iniciarViaje().
      // Se mantiene en el switch por exhaustividad; muestra spinner de transición.
      EstadoViajeActivo.viajeConfirmado => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.success),
              const SizedBox(height: 24),
              Text(
                'Abordaje confirmado. Iniciando viaje...',
                style: const TextStyle(
                    color: AppTheme.onBackground, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      EstadoViajeActivo.enRuta => _PanelEnRuta(
          solicitudId: widget.solicitudId,
          diaActual: _diaActual,
          onCerrarDia: _abrirCierreDia,
        ),
      EstadoViajeActivo.esperandoFinalizacion => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 64, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Todos los días enviados a revisión',
                style: TextStyle(
                    color: AppTheme.onBackground,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Esperando que el solicitante apruebe\nla liquidación y cierre el viaje.',
                style: TextStyle(color: AppTheme.onSurface, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      EstadoViajeActivo.modoPanico => _PanelPanico(
          onNormalizar: () {
            context.read<WsProvider>().desactivarModoPanico();
          },
        ),
    };
  }
}

// ── Paneles ───────────────────────────────────────────────────────────────────

class _PanelAccion extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String descripcion;
  final Color colorBoton;
  final String textoBoton;
  final VoidCallback onPressed;

  const _PanelAccion({
    required this.icon,
    required this.titulo,
    required this.descripcion,
    required this.colorBoton,
    required this.textoBoton,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 80, color: colorBoton),
          const SizedBox(height: 16),
          Text(titulo,
              style: const TextStyle(
                  color: AppTheme.onBackground,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(descripcion,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.onSurface, fontSize: 14)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: colorBoton),
              onPressed: onPressed,
              child: Text(textoBoton),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelEnRuta extends StatelessWidget {
  final int solicitudId;
  final int diaActual;
  final VoidCallback onCerrarDia;
  const _PanelEnRuta({
    required this.solicitudId,
    required this.diaActual,
    required this.onCerrarDia,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'EN RUTA',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.success,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          icon: const Icon(Icons.receipt_long),
          label: const Text('📦 Registrar soporte'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SoportesScreen(
                solicitudId: solicitudId,
                diaNumero: diaActual,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.nights_stay),
          label: const Text('🔚 Cerrar día'),
          onPressed: onCerrarDia,
        ),
      ],
    );
  }
}

class _PanelPanico extends StatelessWidget {
  final VoidCallback onNormalizar;
  const _PanelPanico({required this.onNormalizar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, size: 80, color: AppTheme.error),
          const SizedBox(height: 16),
          const Text(
            '🚨 Modo pánico activo',
            style: TextStyle(
              color: AppTheme.error,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Transmitiendo posición GPS al equipo de seguridad.\n'
            'Presiona cuando la situación se haya normalizado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.onSurface),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            icon: const Icon(Icons.check_circle),
            label: const Text('Situación normalizada'),
            onPressed: onNormalizar,
          ),
        ],
      ),
    );
  }
}

// ── BottomSheet chequeo ───────────────────────────────────────────────────────

class _ChequeoBottomSheet extends StatelessWidget {
  final void Function(String estado) onRespuesta;
  const _ChequeoBottomSheet({required this.onRespuesta});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '⏰ Chequeo horario',
            style: TextStyle(
              color: AppTheme.onBackground,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '¿Cómo está el viaje?',
            style: TextStyle(color: AppTheme.onSurface, fontSize: 16),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('✅ Normal'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onRespuesta('NORMAL');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error),
                  icon: const Icon(Icons.warning),
                  label: const Text('⚠️ Anormal'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onRespuesta('ANORMAL');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
