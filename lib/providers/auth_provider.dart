import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

enum AuthState { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthProvider(this._authService);

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
    if (loggedIn) {
      _userData = await _authService.getUserData();
      _state = AuthState.authenticated;
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

  void forceUnauthenticated() {
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _authService.logout();
    _userData = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }
}
