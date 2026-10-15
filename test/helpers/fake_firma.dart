import 'dart:typed_data';

import 'package:agentreservas_conductor/services/firma_dispositivo.dart';

/// Doble de la llave del aparato: sin Keystore ni biometría reales.
/// Registra lo que se le pide para que las pruebas lo verifiquen.
class FakeFirmaDispositivo implements FirmaDispositivo {
  FakeFirmaDispositivo({
    this.llavePublica = 'LLAVE_PUBLICA_B64',
    this.firmaB64 = 'FIRMA_B64',
    this.errorCrear,
    this.errorFirmar,
    this.existe = false,
  });

  final String llavePublica;
  final String firmaB64;
  final String? errorCrear;
  final String? errorFirmar;
  bool existe;

  int llamadasCrear = 0;
  int llamadasFirmar = 0;
  int llamadasBorrar = 0;
  Uint8List? ultimoMensaje;

  @override
  Future<bool> existeLlave() async => existe;

  @override
  Future<ResultadoFirma> crearLlave() async {
    llamadasCrear++;
    if (errorCrear != null) return ResultadoFirma.fallo(errorCrear!);
    existe = true;
    return ResultadoFirma.exito(llavePublica);
  }

  @override
  Future<ResultadoFirma> firmar(Uint8List mensaje) async {
    llamadasFirmar++;
    ultimoMensaje = mensaje;
    if (errorFirmar != null) return ResultadoFirma.fallo(errorFirmar!);
    return ResultadoFirma.exito(firmaB64);
  }

  @override
  Future<void> borrarLlave() async {
    llamadasBorrar++;
    existe = false;
  }
}
