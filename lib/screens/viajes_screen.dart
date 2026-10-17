import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/viaje.dart';
import '../providers/auth_provider.dart';
import '../providers/viaje_provider.dart';
import '../services/seguimiento_controller.dart';
import '../widgets/estado_badge.dart';
import 'detalle_viaje_screen.dart';
import 'login_screen.dart';

class ViajesScreen extends StatefulWidget {
  const ViajesScreen({super.key});

  @override
  State<ViajesScreen> createState() => _ViajesScreenState();
}

class _ViajesScreenState extends State<ViajesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ViajeProvider>().cargarMisViajes();
      _retomarSeguimiento();
    });
  }

  /// Si la app se cerro o se reinicio con un viaje EN CURSO, el seguimiento se retoma al abrirla:
  /// sin esto, un conductor que reinicia el telefono a mitad de camino quedaria sin rastro hasta
  /// que entrara a la pantalla del viaje.
  void _retomarSeguimiento() {
    if (!mounted) return;
    final enCurso =
        context.read<ViajeProvider>().viajes.where((v) => v.esEnCurso);
    if (enCurso.isEmpty) return;
    unawaited(context.read<SeguimientoController>().iniciar(enCurso.first.id));
  }

  Future<void> _logout() async {
    // Cerrar sesion detiene el seguimiento: ya no es este conductor quien lleva el telefono.
    final seguimiento = context.read<SeguimientoController>();
    final auth = context.read<AuthProvider>();
    await seguimiento.detener();
    await auth.logout();
    if (!mounted) return;
    unawaited(Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final conductorNombre =
        context.select<AuthProvider, String>((a) => a.conductorNombre);
    final viajes = context.watch<ViajeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis Viajes'),
            Text(
              conductorNombre,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.onSurface,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () => context.read<ViajeProvider>().cargarMisViajes(),
        child: _body(viajes),
      ),
    );
  }

  Widget _body(ViajeProvider viajes) {
    if (viajes.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    // Show list first if available — don't hide cached data due to a detail error
    if (viajes.viajes.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: viajes.viajes.length,
        itemBuilder: (_, i) => _ViajeCard(viaje: viajes.viajes[i]),
      );
    }
    if (viajes.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(viajes.error!, style: const TextStyle(color: AppTheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.read<ViajeProvider>().cargarMisViajes(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_outlined,
              color: AppTheme.onSurface, size: 64),
          SizedBox(height: 16),
          Text(
            'No tienes viajes recientes',
            style: TextStyle(color: AppTheme.onSurface, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _ViajeCard extends StatelessWidget {
  final Viaje viaje;
  const _ViajeCard({required this.viaje});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetalleViajeScreen(solicitudId: viaje.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    viaje.token,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  EstadoBadge(
                    estado: viaje.estado,
                    pulsante: viaje.esEnCurso,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (viaje.solicitanteNombre != null) ...[
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: AppTheme.onSurface),
                    const SizedBox(width: 4),
                    Text(
                      viaje.solicitanteNombre!,
                      style: const TextStyle(
                        color: AppTheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              if (viaje.destinoFinalMunicipio != null)
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 14, color: AppTheme.onSurface),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        viaje.destinoFinalMunicipio!,
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
