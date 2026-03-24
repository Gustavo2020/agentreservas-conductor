import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/viaje_provider.dart';
import '../widgets/estado_badge.dart';
import '../widgets/loading_overlay.dart';
import 'viajes_screen.dart';

final _fmt = NumberFormat('#,###', 'es_CO');

class CierreDiaScreen extends StatefulWidget {
  final int solicitudId;
  final int diaNumero;
  const CierreDiaScreen({
    super.key,
    required this.solicitudId,
    required this.diaNumero,
  });

  @override
  State<CierreDiaScreen> createState() => _CierreDiaScreenState();
}

class _CierreDiaScreenState extends State<CierreDiaScreen> {
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<ViajeProvider>()
          .cargarSoportesDia(widget.solicitudId, widget.diaNumero);
    });
  }

  Future<void> _cerrarDia({required bool enviarRevision}) async {
    setState(() => _procesando = true);
    final ok = await context.read<ViajeProvider>().cerrarDia(
          widget.solicitudId,
          diaNumero: widget.diaNumero,
          enviarRevision: enviarRevision,
        );
    if (!mounted) return;
    setState(() => _procesando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enviarRevision
                ? 'Día cerrado y enviado a revisión'
                : 'Día ${widget.diaNumero} cerrado',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      // Retorna true para que ViajeActivoScreen recargue el estado
      // y avance _diaActual al siguiente día.
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<ViajeProvider>().error ?? 'Error cerrando el día'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _cerrarViaje() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Cerrar viaje completo'),
        content: const Text(
            '¿Estás seguro? Esta acción finaliza el viaje y notifica al solicitante.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _procesando = true);
    final ok =
        await context.read<ViajeProvider>().cerrarViaje(widget.solicitudId);
    if (!mounted) return;
    setState(() => _procesando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Viaje finalizado exitosamente'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ViajesScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ViajeProvider>();
    final hayPendientes =
        prov.soportesDia.any((s) => s.pendiente);
    final todosAprobados = prov.soportesDia.isNotEmpty &&
        prov.soportesDia.every((s) => s.aprobado);

    return Scaffold(
      appBar: AppBar(
        title: Text('Cierre — Día ${widget.diaNumero}'),
      ),
      body: LoadingOverlay(
        isLoading: _procesando,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Resumen soportes
            const Text(
              'Soportes del día',
              style: TextStyle(
                  color: AppTheme.onBackground,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (prov.soportesDia.isEmpty)
              const Text('Sin soportes registrados',
                  style: TextStyle(color: AppTheme.onSurface))
            else
              ...prov.soportesDia.map(
                (s) => ListTile(
                  tileColor: AppTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  title: Text(s.tipo,
                      style: const TextStyle(color: AppTheme.onBackground)),
                  subtitle: Text(
                    '\$${_fmt.format(s.monto)}',
                    style: const TextStyle(color: AppTheme.primary),
                  ),
                  trailing: EstadoBadge(estado: s.estado),
                ),
              ),

            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        color: AppTheme.onBackground,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text(
                  '\$${_fmt.format(prov.totalDia)}',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 20),
                ),
              ],
            ),

            if (hayPendientes) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ Hay soportes pendientes de aprobación',
                  style: TextStyle(color: AppTheme.warning, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Cerrar y enviar siempre a revisión del solicitante
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Cerrar día y enviar a revisión'),
              onPressed: () => _cerrarDia(enviarRevision: true),
            ),

            // Cierre total del viaje (si todos los soportes están aprobados)
            if (todosAprobados) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success),
                icon: const Icon(Icons.flag),
                label: const Text('🏁 Cerrar viaje completo'),
                onPressed: _cerrarViaje,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
