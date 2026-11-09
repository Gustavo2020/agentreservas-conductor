import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/textos_demo_alertas.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import 'viajes_screen.dart';

/// Textos de la pantalla de enlace del modo demo (centralizados para aprobación).
class TextosDemo {
  TextosDemo._();

  static const String titulo = 'Viasofia · Demostración';
  static const String instruccion =
      'Escribe el código de 6 dígitos que muestra el panel mientras hay una simulación activa.';
  static const String campo = 'Código de enlace';
  static const String boton = 'Enlazar';
  static const String codigoIncompleto = 'El código tiene 6 dígitos';
  static const String bandaDetalle =
      'MODO DEMO · datos simulados · la ubicación la genera el servidor';
}

/// Reemplaza al login con segundo factor en la APK de demostración.
class CodigoEnlaceScreen extends StatefulWidget {
  const CodigoEnlaceScreen({super.key});

  @override
  State<CodigoEnlaceScreen> createState() => _CodigoEnlaceScreenState();
}

class _CodigoEnlaceScreenState extends State<CodigoEnlaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enlazar() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final ok = await auth.loginDemo(_codigoCtrl.text.trim());
    if (!mounted || !ok) return;
    await navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const ViajesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.select<AuthProvider, bool>((a) => a.loading);
    final error = context.select<AuthProvider, String?>((a) => a.error);
    final motivoFin = context.select<AuthProvider, MotivoFinSesion?>(
        (a) => a.motivoFin);
    // Si la sesión terminó sola (vencida o rechazada por el servidor) se explica por qué hay que
    // volver a enlazar; si el usuario la cerró él mismo, no hace falta.
    final avisoFin = motivoFin == MotivoFinSesion.vencida ||
            motivoFin == MotivoFinSesion.rechazada
        ? TextosSesionDemo.sesionTerminada
        : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(Icons.link, color: AppTheme.primary, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    TextosDemo.titulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    TextosDemo.instruccion,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.onSurface, fontSize: 14),
                  ),
                  if (avisoFin != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      avisoFin,
                      key: const Key('aviso_sesion_terminada'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.primary, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 32),
                  TextFormField(
                    key: const Key('campo_codigo_enlace'),
                    controller: _codigoCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: AppConfig.codigoEnlaceLongitud,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 28, letterSpacing: 8),
                    decoration: const InputDecoration(
                      labelText: TextosDemo.campo,
                      counterText: '',
                    ),
                    validator: (v) => (v ?? '').trim().length ==
                            AppConfig.codigoEnlaceLongitud
                        ? null
                        : TextosDemo.codigoIncompleto,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const Key('error_codigo_enlace'),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: AppTheme.error, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : _enlazar,
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.onPrimary,
                              ),
                            )
                          : const Text(TextosDemo.boton),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
