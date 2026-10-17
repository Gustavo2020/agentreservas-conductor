import 'package:shared_preferences/shared_preferences.dart';

import 'cola_posiciones.dart';

/// Guarda la cola de posiciones en el almacenamiento del teléfono: sobrevive a que la app se
/// cierre o el teléfono se reinicie sin señal.
class AlmacenPrefs implements AlmacenCola {
  static const String _clave = 'cola_posiciones_v1';

  @override
  Future<String?> leer() async =>
      (await SharedPreferences.getInstance()).getString(_clave);

  @override
  Future<void> guardar(String contenido) async {
    await (await SharedPreferences.getInstance()).setString(_clave, contenido);
  }
}
