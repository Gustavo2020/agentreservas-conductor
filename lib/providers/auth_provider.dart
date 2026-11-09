import 'dart:async';

import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

enum AuthState { unknown, authenticated, unauthenticated }

/// Por qué terminó la sesión de la demostración.
enum MotivoFinSesion {
  /// El usuario pulsó «Cerrar sesión».
  manual,

  /// El token venció (a las 6 h).
  vencida,

  /// El servidor la rechazó (401): simulación detenida, código nuevo o desenlace desde el panel.
  rechazada,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  /// Modo demostración: la sesión puede terminar sola (vencimiento, revocación) y siempre se
  /// vuelve a la pantalla del código. La app de operación no cambia.
  final bool demo;
  final DateTime Function() _ahora;
  Timer? _vencimiento;

  AuthProvider(
    this._authService, {
    this.demo = AppConfig.modoDemo,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  MotivoFinSesion? _motivoFin;

  /// Motivo del último fin de sesión, o null si hay sesión / nunca hubo. La pantalla del código lo
  /// usa para explicar por qué tiene que volver a enlazar.
  MotivoFinSesion? get motivoFin => _motivoFin;

  AuthState _state = AuthState.unknown;
  Map<String, dynamic>? _userData;
  String? _error;
  bool _loading = false;

  AuthState get state => _state;
  Map<String, dynamic>? get userData => _userData;
  String? get error => _error;
  bool get loading => _loading;
  bool get isAuthenticated => _state == AuthState.authenticated;

  String get conductorNombre => _userData?['nombre'] as String? ?? 'Conductor';

  // ── Inicialización ─────────────────────────────────────────────────────────

  Future<void> checkAuth() async {
    final loggedIn = await _authService.isLoggedIn();
    if (loggedIn && demo && await _sesionVencida()) {
      await _authService.logout();
      _userData = null;
      _motivoFin = MotivoFinSesion.vencida;
      _state = AuthState.unauthenticated;
    } else if (loggedIn) {
      _userData = await _authService.getUserData();
      _state = AuthState.authenticated;
      await _programarVencimiento();
    } else {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.login(email, password);
    _loading = false;

    if (result.success) {
      _userData = result.userData;
      _state = AuthState.authenticated;
      _error = null;
    } else {
      _error = result.error;
      _state = AuthState.unauthenticated;
    }

    notifyListeners();
    return result.success;
  }

  /// Modo demo: enlaza con el código de 6 dígitos del panel.
  Future<bool> loginDemo(String codigo) async {
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.loginDemo(codigo);
    _loading = false;

    if (result.success) {
      _userData = result.userData;
      _state = AuthState.authenticated;
      _error = null;
      _motivoFin = null;
      await _programarVencimiento();
    } else {
      _error = result.error;
      _state = AuthState.unauthenticated;
    }

    notifyListeners();
    return result.success;
  }

  // ── Fin de sesión en demo ──────────────────────────────────────────────────

  Future<bool> _sesionVencida() async {
    final vence = await _authService.vencimientoSesion();
    return vence != null && !vence.isAfter(_ahora());
  }

  Future<void> _programarVencimiento() async {
    _vencimiento?.cancel();
    _vencimiento = null;
    if (!demo) return;
    final vence = await _authService.vencimientoSesion();
    if (vence == null) return;
    final falta = vence.difference(_ahora());
    // Timer.duration máximo práctico: más allá de ~24 días se reprograma al volver a la app.
    _vencimiento = Timer(falta.isNegative ? Duration.zero : falta,
        () => terminarSesion(MotivoFinSesion.vencida));
  }

  /// Revisa si la sesión venció (la app volvió al primer plano tras horas dormida).
  Future<void> revisarVencimiento() async {
    if (!demo || _state != AuthState.authenticated) return;
    if (await _sesionVencida()) await terminarSesion(MotivoFinSesion.vencida);
  }

  /// Cierra la sesión por una causa ajena al botón: vencimiento o rechazo del servidor (401).
  /// Idempotente: varias llamadas fallidas a la vez cierran una sola vez.
  Future<void> terminarSesion(MotivoFinSesion motivo) async {
    if (_state != AuthState.authenticated) return;
    _vencimiento?.cancel();
    _vencimiento = null;
    // El estado cambia primero: cualquier otra llamada que llegue en medio ya ve la sesión cerrada.
    _state = AuthState.unauthenticated;
    _motivoFin = motivo;
    _userData = null;
    notifyListeners();
    await _authService.logout();
  }

  @override
  void dispose() {
    _vencimiento?.cancel();
    super.dispose();
  }

  void forceUnauthenticated() {
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    _vencimiento?.cancel();
    _vencimiento = null;
    await _authService.logout();
    _userData = null;
    _motivoFin = MotivoFinSesion.manual;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }
}
