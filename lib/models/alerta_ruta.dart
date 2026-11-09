import 'dart:convert';

import '../config/textos_demo_alertas.dart';

/// Aviso de que el vehículo entró a un tramo prohibido (mensaje `TRAMO_PROHIBIDO` del servidor).
class AlertaRuta {
  /// Clave de idempotencia: el mismo aviso reenviado por el servidor produce la misma clave.
  final String id;

  /// Verdadero si el servidor mandó un identificador propio de la alerta (`alerta_id`). Sin él, la
  /// clave se deduce del contenido y solo vale dentro de una ventana de tiempo.
  final bool idDelServidor;

  final int? solicitudId;
  final String mensaje;
  final String? alternativa;
  final String? tramo;

  const AlertaRuta({
    required this.id,
    required this.mensaje,
    this.idDelServidor = false,
    this.solicitudId,
    this.alternativa,
    this.tramo,
  });

  /// Construye la alerta desde el JSON del servidor. El mensaje siempre existe (si el servidor no
  /// lo manda se usa [textoPorDefecto]).
  factory AlertaRuta.deMensaje(
    Map<String, dynamic> data, {
    required String textoPorDefecto,
  }) {
    final mensaje = _texto(data['mensaje']) ?? textoPorDefecto;
    final alt = _texto(data['alternativa']);
    final tramo = _texto(data['tramo']);
    final sol = data['solicitud_id'];
    final solicitudId = sol is int ? sol : int.tryParse('$sol');
    final idServidor = _texto(data['alerta_id']) ?? _texto(data['id']);
    return AlertaRuta(
      id: idServidor ?? '${solicitudId ?? '-'}|${tramo ?? '-'}|$mensaje',
      idDelServidor: idServidor != null,
      solicitudId: solicitudId,
      mensaje: mensaje,
      alternativa: alt,
      tramo: tramo,
    );
  }

  static String? _texto(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  /// Texto completo para mostrar: el mensaje y, si falta en él, la ruta permitida.
  String get texto => alternativa == null || mensaje.contains(alternativa!)
      ? mensaje
      : '$mensaje\n\n${TextosAlertaRuta.notificacionRuta}: $alternativa';

  /// Carga de la notificación del sistema: lo justo para reabrir el aviso al tocarla.
  String toPayload() => jsonEncode({
        'id': id,
        'srv': idDelServidor,
        'sol': solicitudId,
        'msg': mensaje,
        'alt': alternativa,
        'tramo': tramo,
      });

  static AlertaRuta? dePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final j = jsonDecode(payload);
      if (j is! Map<String, dynamic>) return null;
      final id = j['id'];
      final msg = j['msg'];
      if (id is! String || msg is! String) return null;
      return AlertaRuta(
        id: id,
        idDelServidor: j['srv'] == true,
        solicitudId: j['sol'] as int?,
        mensaje: msg,
        alternativa: j['alt'] as String?,
        tramo: j['tramo'] as String?,
      );
    } on Object {
      return null;
    }
  }
}
