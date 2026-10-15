import 'dart:convert';

import 'package:http/http.dart' as http;

http.Response respuestaJson(Map<String, dynamic> cuerpo, [int status = 200]) =>
    http.Response(
      jsonEncode(cuerpo),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Servidor falso del primer login: la clave da un paso `enrolar` y el
/// enrolamiento entrega la sesión. Registra los cuerpos recibidos.
class ServidorFalso {
  ServidorFalso({
    this.token = 'tok',
    this.nombre = 'Conductor',
    this.dispositivoId = 7,
    this.reto = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=',
  });

  final String token;
  final String nombre;
  final int dispositivoId;
  final String reto;

  /// Si es true, `conductor-login` responde `firmar` (el aparato ya existe).
  bool aparatoEnrolado = false;
  final Map<String, Map<String, dynamic>> recibidos = {};
  final List<String> rutas = [];

  Future<http.Response> manejar(http.Request r) async {
    final ruta = r.url.path;
    rutas.add(ruta);
    final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
    recibidos[ruta] = cuerpo;
    switch (ruta) {
      case '/api/auth/conductor-login':
        if (aparatoEnrolado) {
          return respuestaJson({
            'step': 'firmar',
            'session': 'PRE',
            'dispositivo_id': dispositivoId,
            'reto': reto,
          });
        }
        return respuestaJson({'step': 'enrolar', 'session': 'PRE'});
      case '/api/auth/conductor-enrolar':
      case '/api/auth/conductor-firmar':
        return respuestaJson({
          'access_token': token,
          'nombre': nombre,
          'conductor_id': 3,
          'dispositivo_id': dispositivoId,
          'expira_en': 360,
        });
    }
    return respuestaJson({'detail': 'ruta no simulada: $ruta'}, 404);
  }
}
