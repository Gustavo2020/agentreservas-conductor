import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/checklist.dart';
import '../models/trayecto.dart';
import '../models/viaje.dart' show Viajero;
import '../providers/viaje_provider.dart';
import '../providers/ws_provider.dart';
import '../widgets/estado_badge.dart';
import '../widgets/loading_overlay.dart';
import 'checklist_screen.dart';
import 'viaje_activo_screen.dart';

class DetalleViajeScreen extends StatefulWidget {
  final int solicitudId;
  const DetalleViajeScreen({super.key, required this.solicitudId});

  @override
  State<DetalleViajeScreen> createState() => _DetalleViajeScreenState();
}

class _DetalleViajeScreenState extends State<DetalleViajeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _rutaAceptada = false;
  bool _aceptando = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context
          .read<ViajeProvider>()
          .cargarDetalleViaje(widget.solicitudId);
      if (mounted) {
        final viaje = context.read<ViajeProvider>().viajeActual;
        if (viaje != null && viaje.rutaAceptada) {
          setState(() => _rutaAceptada = true);
        }
        context.read<WsProvider>().addListener(_onWsUpdate);
      }
    });
  }

  void _onWsUpdate() {
    if (!mounted) return;
    final ws = context.read<WsProvider>();
    if (ws.checklistAprobado) {
      ws.limpiarChecklistAprobado();
      context.read<ViajeProvider>().cargarDetalleViaje(widget.solicitudId);
    }
  }

  @override
  void dispose() {
    context.read<WsProvider>().removeListener(_onWsUpdate);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _aceptarRuta() async {
    setState(() => _aceptando = true);
    final ok =
        await context.read<ViajeProvider>().aceptarRuta(widget.solicitudId);
    if (mounted) {
      setState(() {
        _aceptando = false;
        if (ok) _rutaAceptada = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ViajeProvider>();
    final viaje = prov.viajeActual;

    return Scaffold(
      appBar: AppBar(
        title: Text(viaje?.token ?? 'Detalle del viaje'),
        actions: [
          if (viaje?.esEnCurso == true ||
              (viaje?.estado == 'APROBADO' &&
                  viaje?.checklist?.aprobado == true))
            TextButton.icon(
              icon: const Icon(Icons.play_arrow, color: AppTheme.primary),
              label: const Text(
                'Viaje activo',
                style: TextStyle(color: AppTheme.primary),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ViajeActivoScreen(solicitudId: widget.solicitudId),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.onSurface,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Ruta'),
            Tab(text: 'Checklist'),
            Tab(text: 'Estado'),
          ],
        ),
      ),
      body: LoadingOverlay(
        isLoading: prov.loading,
        child: viaje == null && !prov.loading && prov.error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.error, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        prov.error ?? 'Error cargando el viaje',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.error),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context
                            .read<ViajeProvider>()
                            .cargarDetalleViaje(widget.solicitudId),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : viaje == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _TabRuta(
                        trayectos: viaje.trayectos,
                        viajeros: viaje.viajeros,
                        rutaAceptada:
                            _rutaAceptada || viaje.estado == 'CANCELADO',
                        aceptando: _aceptando,
                        onAceptar: _aceptarRuta,
                      ),
                      _TabChecklist(
                        solicitudId: widget.solicitudId,
                        checklist: viaje.checklist,
                      ),
                      _TabEstado(estado: viaje.estado),
                    ],
                  ),
      ),
    );
  }
}

// ── Tab Ruta ──────────────────────────────────────────────────────────────────

class _TabRuta extends StatelessWidget {
  final List<Trayecto> trayectos;
  final List<Viajero> viajeros;
  final bool rutaAceptada;
  final bool aceptando;
  final VoidCallback onAceptar;

  const _TabRuta({
    required this.trayectos,
    required this.viajeros,
    required this.rutaAceptada,
    required this.aceptando,
    required this.onAceptar,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (trayectos.isEmpty)
          const Center(
            child: Text('Sin trayectos registrados',
                style: TextStyle(color: AppTheme.onSurface)),
          )
        else
          ...trayectos.map(
            (t) => _TrayectoTile(t: t),
          ),
        if (viajeros.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('👥 Viajeros',
                    style: TextStyle(
                        color: AppTheme.onBackground,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                ...viajeros.map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 14, color: AppTheme.onSurface),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              v.esSolicitante
                                  ? '${v.nombre} (solicitante)'
                                  : v.nombre,
                              style: TextStyle(
                                color: v.esSolicitante
                                    ? AppTheme.primary
                                    : AppTheme.onBackground,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (!rutaAceptada)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: aceptando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Confirmar revisión de ruta'),
              onPressed: aceptando ? null : onAceptar,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.success),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.success),
                SizedBox(width: 8),
                Text('Ruta confirmada',
                    style: TextStyle(color: AppTheme.success)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrayectoTile extends StatelessWidget {
  final Trayecto t;
  const _TrayectoTile({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${t.diaNumero}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.fecha != null)
                  Text(
                    t.fecha!,
                    style: const TextStyle(
                        color: AppTheme.onSurface, fontSize: 11),
                  ),
                if (t.horaSalida != null)
                  Text(
                    '🕐 ${t.horaSalida}',
                    style: const TextStyle(
                        color: AppTheme.onSurface, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.radio_button_checked,
                        size: 14, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (t.origenMunicipio != null)
                            Text(t.origenMunicipio!,
                                style: const TextStyle(
                                    color: AppTheme.onBackground,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          if (t.origenDireccion != null &&
                              t.origenDireccion!.isNotEmpty)
                            Text(t.origenDireccion!,
                                style: const TextStyle(
                                    color: AppTheme.onSurface, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Column(
                      children: List.generate(
                          3,
                          (_) => const Icon(Icons.more_vert,
                              size: 12, color: AppTheme.onSurface))),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on,
                        size: 14, color: AppTheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        t.destino ?? '—',
                        style: const TextStyle(
                            color: AppTheme.onBackground, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                if (t.pernoctaMunicipio != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '🌙 Pernoctada: ${t.pernoctaMunicipio}',
                      style: const TextStyle(
                          color: AppTheme.onSurface, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Checklist ─────────────────────────────────────────────────────────────

class _TabChecklist extends StatelessWidget {
  final int solicitudId;
  final Checklist? checklist;

  const _TabChecklist({required this.solicitudId, required this.checklist});

  void _irAChecklist(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => ChecklistScreen(solicitudId: solicitudId),
    ))
        .then((_) {
      if (context.mounted) {
        context.read<ViajeProvider>().cargarDetalleViaje(solicitudId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── Sin checklist iniciado: solo botón amarillo, sin texto extra ──────────
    if (checklist == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.checklist),
              label: const Text('Completar checklist'),
              onPressed: () => _irAChecklist(context),
            ),
          ),
        ),
      );
    }

    final cl = checklist!;

    // ── Aprobado ──────────────────────────────────────────────────────────────
    if (cl.aprobado) {
      return _buildEstadoPanel(
        icon: Icons.verified,
        color: AppTheme.success,
        titulo: 'Checklist aprobado',
        subtitulo: cl.mensajeAprobacion?.isNotEmpty == true
            ? cl.mensajeAprobacion!
            : 'El responsable aprobó el checklist. Puedes iniciar el viaje.',
        mostrarBotonIniciar: true,
        mostrarBotonVolver: true,
        context: context,
        solicitudId: solicitudId,
      );
    }

    // ── Rechazado ─────────────────────────────────────────────────────────────
    if (cl.rechazado) {
      return _buildEstadoPanel(
        icon: Icons.cancel,
        color: AppTheme.error,
        titulo: 'Checklist rechazado',
        subtitulo: cl.mensajeAprobacion?.isNotEmpty == true
            ? cl.mensajeAprobacion!
            : 'El responsable rechazó el checklist.',
        mostrarBotonVolver: true,
        mostrarBotonEditar: true,
        context: context,
      );
    }

    // ── Enviado — en revisión ─────────────────────────────────────────────────
    if (cl.enviadoRevision) {
      return _buildEstadoPanel(
        icon: Icons.hourglass_top,
        color: AppTheme.warning,
        titulo: 'Checklist en Revisión',
        subtitulo: 'El responsable está revisando el checklist.',
        mostrarBotonVolver: true,
        context: context,
      );
    }

    // ── Incompleto — ir a completar ───────────────────────────────────────────
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.checklist),
            label: const Text('Completar checklist'),
            onPressed: () => _irAChecklist(context),
          ),
        ),
      ),
    );
  }

  Widget _buildEstadoPanel({
    required IconData icon,
    required Color color,
    required String titulo,
    required String subtitulo,
    required BuildContext context,
    bool mostrarBotonVolver = false,
    bool mostrarBotonEditar = false,
    bool mostrarBotonIniciar = false,
    int? solicitudId,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 72),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 14),
              ),
            ),
            const SizedBox(height: 24),
            if (mostrarBotonIniciar && solicitudId != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary),
                  icon: const Icon(Icons.directions_car),
                  label: const Text('Iniciar viaje'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ViajeActivoScreen(solicitudId: solicitudId),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (mostrarBotonVolver)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver'),
                ),
              ),
            if (mostrarBotonEditar) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar y reenviar checklist'),
                  onPressed: () => _irAChecklist(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Tab Estado ────────────────────────────────────────────────────────────────

class _TabEstado extends StatelessWidget {
  final String estado;
  const _TabEstado({required this.estado});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EstadoBadge(estado: estado, pulsante: estado == 'EN_CURSO'),
          const SizedBox(height: 16),
          Text(
            _descripcion(estado),
            style: const TextStyle(color: AppTheme.onSurface),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _descripcion(String estado) => switch (estado) {
        'APROBADO' => 'El viaje está aprobado y listo para iniciar.',
        'EN_CURSO' => 'El viaje está en progreso.',
        'FINALIZADO' => 'El viaje ha sido cerrado exitosamente.',
        'CANCELADO' =>
          'Este viaje fue cancelado. El conductor y vehículo han sido liberados.',
        _ => 'Estado: $estado',
      };
}
