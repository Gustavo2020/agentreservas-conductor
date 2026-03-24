import 'package:flutter/foundation.dart';
import '../models/viaje.dart';
import '../models/soporte.dart';
import '../services/api_service.dart';

class ViajeProvider extends ChangeNotifier {
  final ApiService _api;

  ViajeProvider(this._api);

  List<Viaje> _viajes = [];
  Viaje? _viajeActual;
  List<Soporte> _soportesDia = [];
  double _totalDia = 0;
  bool _loading = false;
  String? _error;

  List<Viaje> get viajes => _viajes;
  Viaje? get viajeActual => _viajeActual;
  List<Soporte> get soportesDia => _soportesDia;
  double get totalDia => _totalDia;
  bool get loading => _loading;
  String? get error => _error;

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  // ── Lista de viajes ────────────────────────────────────────────────────────

  Future<void> cargarMisViajes() async {
    _setLoading(true);
    _error = null;
    try {
      final raw = await _api.getMisViajes();
      _viajes = raw
          .map((j) => Viaje.fromJson(j as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error cargando viajes: $e';
    } finally {
      _setLoading(false);
    }
  }

  // ── Detalle ────────────────────────────────────────────────────────────────

  Future<void> cargarDetalleViaje(int id) async {
    _setLoading(true);
    _error = null;
    try {
      final data = await _api.getDetalleViaje(id);
      // El endpoint retorna {detalle, trayectos, checklist, cierres, viajeros}
      final detalleJson = {
        ...(data['detalle'] as Map<String, dynamic>? ?? {}),
        'trayectos':      data['trayectos'],
        'checklist':      data['checklist'],
        'viajeros':       data['viajeros'],
        'ruta_aceptada':  data['ruta_aceptada'],
        'viaje_iniciado': data['viaje_iniciado'],
        'en_sitio':       data['en_sitio'],
        'cierres':        data['cierres'],
      };
      _viajeActual = Viaje.fromJson(detalleJson);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error cargando detalle: $e';
    } finally {
      _setLoading(false);
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<bool> aceptarRuta(int solicitudId) async {
    try {
      await _api.aceptarRuta(solicitudId);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> reportarEnSitio(
    int solicitudId, {
    required double lat,
    required double lng,
  }) async {
    try {
      await _api.reportarEnSitio(solicitudId, lat: lat, lng: lng);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> iniciarViaje(int solicitudId) async {
    try {
      await _api.iniciarViaje(solicitudId);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cerrarViaje(int solicitudId) async {
    try {
      await _api.cerrarViaje(solicitudId);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Soportes ───────────────────────────────────────────────────────────────

  Future<void> cargarSoportesDia(int solicitudId, int dia) async {
    _setLoading(true);
    try {
      final data = await _api.getSoportesDia(solicitudId, dia);
      _soportesDia = (data['soportes'] as List<dynamic>? ?? [])
          .map((j) => Soporte.fromJson(j as Map<String, dynamic>))
          .toList();
      _totalDia = _soportesDia.fold(0.0, (sum, s) => sum + s.monto);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> cerrarDia(
    int solicitudId, {
    required int diaNumero,
    required bool enviarRevision,
  }) async {
    try {
      await _api.cerrarDia(solicitudId,
          diaNumero: diaNumero, enviarRevision: enviarRevision);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }
}
