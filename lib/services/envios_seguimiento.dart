import 'api_service.dart';
import 'cola_posiciones.dart';
import 'panico_service.dart';
import 'seguimiento_service.dart';

/// Traduce la respuesta HTTP al lenguaje del seguimiento: qué hacer con lo que se mandó.
ResultadoLote resultadoDeLote(int? estado) {
  if (estado == null) return ResultadoLote.recibido;
  // 422: el lote está mal formado; reintentarlo lo bloquearía para siempre.
  if (estado == 422) return ResultadoLote.omitir;
  // 403/404/409: el viaje ya no es de este conductor o ya no está en curso.
  if (estado == 403 || estado == 404 || estado == 409) {
    return ResultadoLote.descartar;
  }
  // Todo lo demás (401 con el token por renovar, 5xx, timeouts) se reintenta.
  return ResultadoLote.reintentar;
}

ResultadoPanico resultadoDePanico(int? estado) {
  if (estado == null) return ResultadoPanico.confirmado;
  // El viaje ya no está en curso o no es de este conductor, o la posición no sirve: no se
  // reintenta, se avisa para que llame a operaciones.
  if (estado == 403 || estado == 404 || estado == 409 || estado == 422) {
    return ResultadoPanico.rechazado;
  }
  return ResultadoPanico.reintentar;
}

EnviarLote lotePorHttp(ApiService api) =>
    (int id, List<PuntoGps> puntos) async {
      try {
        await api.enviarPosiciones(id, puntos.map((p) => p.toJson()).toList());
        return resultadoDeLote(null);
      } on ApiException catch (e) {
        return resultadoDeLote(e.statusCode);
      } on Object {
        return ResultadoLote.reintentar; // sin red
      }
    };

EnviarPanico panicoPorHttp(ApiService api) =>
    (int id, double lat, double lng) async {
      try {
        await api.pulsarPanico(id, lat: lat, lng: lng);
        return resultadoDePanico(null);
      } on ApiException catch (e) {
        return resultadoDePanico(e.statusCode);
      } on Object {
        return ResultadoPanico.reintentar; // sin red
      }
    };
