import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/app_config.dart';
import 'auth_service.dart';
import 'log_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// HTTP client con interceptor JWT automático.
/// Lanza [ApiException] en errores HTTP y redirige a login si el token expiró.
class ApiService {
  final AuthService _auth;
  final http.Client _httpClient;

  ApiService(this._auth, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  // ── Helpers internos ───────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _parseBody(http.Response response) {
    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic>) return body;
    return {'data': body};
  }

  void _checkStatus(http.Response response, String path) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      final msg =
          _parseBody(response)['detail'] as String? ?? 'Sin autorización';
      AppLogger.warning('ApiService: acceso denegado',
          context: {'path': path, 'status': '${response.statusCode}'});
      throw ApiException(response.statusCode, msg);
    }
    if (response.statusCode >= 400) {
      final detail = _parseBody(response)['detail'] as String? ??
          'Error ${response.statusCode}';
      AppLogger.error(
        'ApiService: error HTTP',
        ApiException(response.statusCode, detail),
        context: {'path': path, 'status': '${response.statusCode}'},
      );
      throw ApiException(response.statusCode, detail);
    }
  }

  // ── Métodos HTTP ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('${AppConfig.baseUrl}$path'),
            headers: await _headers(),
          )
          .timeout(AppConfig.httpTimeout);
      _checkStatus(response, path);
      return _parseBody(response);
    } on ApiException {
      rethrow;
    } on Exception catch (e, st) {
      AppLogger.error('ApiService: timeout o error de red en GET', e,
          stackTrace: st, context: {'path': path});
      rethrow;
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('${AppConfig.baseUrl}$path'),
            headers: await _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(AppConfig.httpTimeout);
      _checkStatus(response, path);
      return _parseBody(response);
    } on ApiException {
      rethrow;
    } on Exception catch (e, st) {
      AppLogger.error('ApiService: timeout o error de red en POST', e,
          stackTrace: st, context: {'path': path});
      rethrow;
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required Uint8List fileBytes,
    required String filename,
    required String contentType,
  }) async {
    try {
      final token = await _auth.getToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}$path'),
      );
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);
      request.files.add(http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ));

      final streamed = await request.send().timeout(AppConfig.httpTimeout);
      final response = await http.Response.fromStream(streamed);
      _checkStatus(response, path);
      return _parseBody(response);
    } on ApiException {
      rethrow;
    } on Exception catch (e, st) {
      AppLogger.error('ApiService: error en multipart POST', e,
          stackTrace: st, context: {'path': path});
      rethrow;
    }
  }

  // ── Endpoints Conductor ────────────────────────────────────────────────────

  Future<List<dynamic>> getMisViajes() async {
    final data = await get('/api/conductor/mis-viajes');
    return data['viajes'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> getDetalleViaje(int id) async {
    return get('/api/conductor/viajes/$id');
  }

  Future<void> aceptarRuta(int solicitudId) async {
    await post('/api/conductor/viajes/$solicitudId/aceptar-ruta');
  }

  Future<Map<String, dynamic>> iniciarChecklist(int solicitudId) async {
    return post('/api/conductor/viajes/$solicitudId/checklist/iniciar');
  }

  Future<void> enviarChecklist(int solicitudId) async {
    await post('/api/conductor/viajes/$solicitudId/checklist/enviar');
  }

  Future<void> reportarEnSitio(
    int solicitudId, {
    required double lat,
    required double lng,
  }) async {
    await post(
      '/api/conductor/viajes/$solicitudId/en-sitio?lat=$lat&lng=$lng',
    );
  }

  Future<void> iniciarViaje(int solicitudId) async {
    await post('/api/conductor/viajes/$solicitudId/iniciar-viaje');
  }

  /// Manda un lote de posiciones medidas por el teléfono (cada una con su hora de medida `t`).
  /// Lo usa la cola local al volver la señal. El servidor decide cuáles guarda.
  Future<Map<String, dynamic>> enviarPosiciones(
    int solicitudId,
    List<Map<String, dynamic>> puntos,
  ) async {
    return post('/api/conductor/viajes/$solicitudId/posiciones',
        body: {'puntos': puntos});
  }

  /// El botón de pánico por HTTP: el respaldo del WebSocket (no depende de que el socket esté
  /// abierto). La posición es obligatoria: una alarma sin lugar no dice a dónde enviar ayuda.
  Future<Map<String, dynamic>> pulsarPanico(
    int solicitudId, {
    required double lat,
    required double lng,
  }) async {
    return post('/api/conductor/viajes/$solicitudId/panico',
        body: {'lat': lat, 'lng': lng});
  }

  Future<Map<String, dynamic>> registrarChequeo(
    int solicitudId, {
    required String estado,
    required double lat,
    required double lng,
    required int diaNumero,
  }) async {
    return post('/api/conductor/viajes/$solicitudId/chequeo', body: {
      'estado': estado,
      'lat': lat,
      'lng': lng,
      'dia_numero': diaNumero,
    });
  }

  Future<Map<String, dynamic>> getSoportesDia(
    int solicitudId,
    int dia,
  ) async {
    return get('/api/conductor/viajes/$solicitudId/soportes/$dia');
  }

  Future<Map<String, dynamic>> subirSoporte(
    int solicitudId, {
    required String tipo,
    required double monto,
    required int diaNumero,
    required int trayectoId,
    required Uint8List fileBytes,
    required String filename,
    required String contentType,
  }) async {
    return postMultipart(
      '/api/conductor/viajes/$solicitudId/soportes'
      '?tipo=$tipo&monto=$monto&dia_numero=$diaNumero&trayecto_id=$trayectoId',
      fields: {},
      fileField: 'archivo',
      fileBytes: fileBytes,
      filename: filename,
      contentType: contentType,
    );
  }

  Future<Map<String, dynamic>> cerrarDia(
    int solicitudId, {
    required int diaNumero,
    required bool enviarRevision,
  }) async {
    return post('/api/conductor/viajes/$solicitudId/soportes/cerrar-dia',
        body: {
          'dia_numero': diaNumero,
          'enviar_revision': enviarRevision,
        });
  }

  Future<void> cerrarViaje(int solicitudId) async {
    await post('/api/conductor/viajes/$solicitudId/cerrar-viaje');
  }
}
