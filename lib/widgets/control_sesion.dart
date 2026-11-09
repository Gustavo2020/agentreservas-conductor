import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';
import '../services/log_service.dart';

/// Lleva la app de vuelta a la pantalla de entrada cuando la sesión de la DEMOSTRACIÓN termina,
/// sea cual sea el motivo y la pantalla donde esté el usuario: botón «Cerrar sesión», token
/// vencido (6 h), 401 del servidor (simulación detenida, código nuevo, desenlace desde el panel).
///
/// La [puerta] (decide entre pantalla del código y lista de viajes) reemplaza TODA la pila de
/// pantallas, así que la app de operación (correo y contraseña) nunca es alcanzable desde aquí. En
/// la app de operación ([demo] falso) no hace nada.
class ControlSesion {
  final AuthProvider auth;
  final GlobalKey<NavigatorState> navegador;
  final Future<void> Function() limpiar;
  final Widget Function() puerta;
  final bool demo;

  ControlSesion({
    required this.auth,
    required this.navegador,
    required this.limpiar,
    required this.puerta,
    required this.demo,
  });

  AuthState? _previo;

  void iniciar() {
    _previo = auth.state;
    auth.addListener(_alCambiar);
  }

  void dispose() => auth.removeListener(_alCambiar);

  void _alCambiar() {
    final previo = _previo;
    final ahora = auth.state;
    _previo = ahora;
    if (!demo) return;
    if (previo == AuthState.authenticated &&
        ahora == AuthState.unauthenticated) {
      unawaited(_terminar());
    }
  }

  Future<void> _terminar() async {
    // Primero se sale de las pantallas del viaje; después se limpia lo que dejaron.
    unawaited(navegador.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => puerta()),
          (_) => false,
        ) ??
        Future<void>.value());
    try {
      await limpiar();
    } on Object catch (e, st) {
      AppLogger.error('ControlSesion: error al limpiar la sesión', e,
          stackTrace: st);
    }
  }
}
