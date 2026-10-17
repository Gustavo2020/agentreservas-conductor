import 'dart:convert';

/// Una posición medida por el teléfono, con la HORA EN QUE SE MIDIÓ (`tMs`, milisegundos desde
/// 1970). Esa hora es la que importa: una posición que se reenvía al volver la señal debe quedar
/// en el expediente del viaje con la hora de cuando se tomó, no con la de cuando llegó.
class PuntoGps {
  final double lat;
  final double lng;
  final int tMs;

  const PuntoGps(this.lat, this.lng, this.tMs);

  /// Como lo espera `POST /api/conductor/viajes/{id}/posiciones` (`t` en milisegundos).
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 't': tMs};

  factory PuntoGps.fromJson(Map<String, dynamic> json) => PuntoGps(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
        (json['t'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is PuntoGps &&
      other.lat == lat &&
      other.lng == lng &&
      other.tMs == tMs;

  @override
  int get hashCode => Object.hash(lat, lng, tMs);
}

/// Dónde se guarda la cola entre ejecuciones de la app (una implementación real usa
/// SharedPreferences; las pruebas usan una en memoria). Si la app se cierra o el teléfono se
/// reinicia sin señal, lo medido no se pierde.
abstract class AlmacenCola {
  Future<String?> leer();
  Future<void> guardar(String contenido);
}

/// Cola local de posiciones por enviar. Tiene un TOPE: sin señal por horas no puede crecer sin
/// límite (memoria y disco del teléfono); al llenarse se descarta lo MÁS VIEJO, porque lo más
/// reciente es lo que dice dónde está el vehículo ahora.
class ColaPosiciones {
  final AlmacenCola _almacen;
  final int maximo;
  final List<PuntoGps> _puntos = [];

  ColaPosiciones(this._almacen, {this.maximo = 500});

  int get longitud => _puntos.length;
  bool get vacia => _puntos.isEmpty;

  /// Recupera lo que quedó guardado. Un contenido dañado se ignora (se empieza vacía): una cola
  /// ilegible no debe impedir seguir al conductor.
  Future<void> cargar() async {
    _puntos.clear();
    final texto = await _almacen.leer();
    if (texto == null || texto.isEmpty) return;
    try {
      final lista = jsonDecode(texto) as List<dynamic>;
      _puntos.addAll(
        lista.map((e) => PuntoGps.fromJson(e as Map<String, dynamic>)),
      );
    } on Object {
      _puntos.clear();
    }
  }

  Future<void> agregar(PuntoGps p) async {
    _puntos.add(p);
    // Se descarta lo más viejo hasta caber.
    while (_puntos.length > maximo) {
      _puntos.removeAt(0);
    }
    await _guardar();
  }

  /// Los primeros [n] puntos (los más viejos), SIN quitarlos: solo se quitan al confirmar que el
  /// servidor los recibió. Si el envío falla, siguen en la cola.
  List<PuntoGps> proximoLote(int n) => _puntos.take(n).toList();

  /// El servidor recibió los primeros [n]: se quitan.
  Future<void> confirmar(int n) async {
    _puntos.removeRange(0, n.clamp(0, _puntos.length));
    await _guardar();
  }

  Future<void> vaciar() async {
    _puntos.clear();
    await _guardar();
  }

  Future<void> _guardar() =>
      _almacen.guardar(jsonEncode(_puntos.map((p) => p.toJson()).toList()));
}
