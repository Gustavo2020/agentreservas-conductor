import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import 'codigo_enlace_screen.dart';
import 'login_screen.dart';
import 'viajes_screen.dart';

/// Decide qué pantalla mostrar según la sesión: carga, lista de viajes o entrada.
///
/// La entrada es la pantalla del código de enlace en la demostración y el login con correo y
/// contraseña en la app de operación. En demo el login de operación no se construye jamás.
class PuertaSesion extends StatefulWidget {
  final bool demo;
  const PuertaSesion({super.key, this.demo = AppConfig.modoDemo});

  @override
  State<PuertaSesion> createState() => _PuertaSesionState();
}

class _PuertaSesionState extends State<PuertaSesion> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<AuthProvider>().checkAuth();
      } catch (_) {
        // Si el almacenamiento seguro falla, se trata como sin sesión.
        if (mounted) context.read<AuthProvider>().forceUnauthenticated();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return switch (auth.state) {
      AuthState.unknown => const Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
      AuthState.authenticated => ViajesScreen(demo: widget.demo),
      AuthState.unauthenticated =>
        widget.demo ? const CodigoEnlaceScreen() : const LoginScreen(),
    };
  }
}
