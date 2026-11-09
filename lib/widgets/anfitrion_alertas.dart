import 'dart:async';

import 'package:flutter/material.dart';

import '../config/textos_demo_alertas.dart';
import '../providers/auth_provider.dart';
import '../services/gestor_alerta_ruta.dart';
import 'dialogo_alerta_ruta.dart';

/// Muestra, sobre CUALQUIER pantalla, el diálogo de la alerta de ruta prohibida y los diálogos de
/// permisos. Vive a nivel de la app (usa la llave del `Navigator`), así que no depende de que la
/// pantalla del viaje esté abierta. Solo muestra algo con la sesión activa.
class AnfitrionAlertas {
  final GestorAlertaRuta gestor;
  final AuthProvider auth;
  final GlobalKey<NavigatorState> navegador;

  AnfitrionAlertas({
    required this.gestor,
    required this.auth,
    required this.navegador,
  });

  bool _mostrando = false;
  bool _permisosPedidos = false;

  void iniciar() {
    gestor.addListener(_revisar);
    auth.addListener(_alCambiarSesion);
  }

  void dispose() {
    gestor.removeListener(_revisar);
    auth.removeListener(_alCambiarSesion);
  }

  void _alCambiarSesion() {
    if (!auth.isAuthenticated) {
      _permisosPedidos = false;
      return;
    }
    _revisar();
    if (!_permisosPedidos) {
      _permisosPedidos = true;
      unawaited(_pedirPermisos());
    }
  }

  Future<void> _pedirPermisos() async {
    // Se espera a que la pantalla de la sesión ya esté pintada.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final ctx = navegador.currentContext;
    if (ctx == null || !auth.isAuthenticated) return;
    await gestor.prepararPermisos(
      explicarNotificaciones: () => _preguntar(
        titulo: TextosAlertaRuta.permisoTitulo,
        explicacion: TextosAlertaRuta.permisoExplicacion,
        si: TextosAlertaRuta.permisoContinuar,
        no: TextosAlertaRuta.permisoAhoraNo,
      ),
      explicarBateria: () => _preguntar(
        titulo: TextosAlertaRuta.bateriaTitulo,
        explicacion: TextosAlertaRuta.bateriaExplicacion,
        si: TextosAlertaRuta.bateriaPermitir,
        no: TextosAlertaRuta.bateriaAhoraNo,
      ),
    );
  }

  Future<bool> _preguntar({
    required String titulo,
    required String explicacion,
    required String si,
    required String no,
  }) async {
    final ctx = navegador.currentContext;
    if (ctx == null) return false;
    return confirmarConExplicacion(ctx,
        titulo: titulo, explicacion: explicacion, si: si, no: no);
  }

  void _revisar() {
    if (_mostrando || !auth.isAuthenticated) return;
    final ctx = navegador.currentContext;
    if (ctx == null || gestor.pendiente == null) return;
    final alerta = gestor.tomarPendiente();
    if (alerta == null) return;
    _mostrando = true;
    unawaited(() async {
      try {
        await mostrarAlertaRuta(ctx, alerta);
      } finally {
        _mostrando = false;
        await gestor.alertaAtendida();
        // Pudo llegar otra alerta mientras el diálogo estaba abierto.
        _revisar();
      }
    }());
  }
}
