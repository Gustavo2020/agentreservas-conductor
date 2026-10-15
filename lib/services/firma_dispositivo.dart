import 'dart:typed_data';

import 'package:biometric_signature/biometric_signature.dart';

import '../config/app_config.dart';
import 'log_service.dart';

/// Resultado de una operación con la llave del aparato.
class ResultadoFirma {
  final bool ok;

  /// Llave pública (base64 DER) al crear, o firma (base64) al firmar.
  final String? valor;

  /// Mensaje apto para mostrar a la persona cuando [ok] es false.
  final String? error;

  const ResultadoFirma._({required this.ok, this.valor, this.error});

  factory ResultadoFirma.exito(String valor) =>
      ResultadoFirma._(ok: true, valor: valor);

  factory ResultadoFirma.fallo(String error) =>
      ResultadoFirma._(ok: false, error: error);
}

/// Llave del aparato: segundo factor del conductor.
///
/// La llave privada vive en hardware (Keystore/StrongBox) y solo se usa tras
/// verificar huella, rostro o PIN del sistema. La biometría nunca sale del
/// teléfono: el servidor solo ve la firma.
abstract class FirmaDispositivo {
  Future<bool> existeLlave();

  /// Crea una llave nueva (pide verificar al usuario). Devuelve la pública.
  Future<ResultadoFirma> crearLlave();

  /// Firma [mensaje] con la llave (pide verificar al usuario).
  Future<ResultadoFirma> firmar(Uint8List mensaje);

  Future<void> borrarLlave();
}

/// Implementación real sobre `biometric_signature`.
class FirmaDispositivoBiometrica implements FirmaDispositivo {
  final BiometricSignature _plugin;

  FirmaDispositivoBiometrica({BiometricSignature? plugin})
      : _plugin = plugin ?? BiometricSignature();

  @override
  Future<bool> existeLlave() async {
    final info = await _plugin.getKeyInfo(keyAlias: AppConfig.llaveAlias);
    return info.exists ?? false;
  }

  @override
  Future<ResultadoFirma> crearLlave() async {
    final r = await _plugin.createKeys(
      keyAlias: AppConfig.llaveAlias,
      keyFormat: KeyFormat.base64,
      promptMessage: 'Confirma tu identidad para registrar este teléfono',
      config: CreateKeysConfig(
        // El servidor solo acepta ECDSA P-256.
        signatureType: SignatureType.ecdsa,
        enforceBiometric: true,
        // PIN o patrón del teléfono como alternativa a la huella: así lo pidió
        // el negocio. Con esa alternativa, invalidar la llave al agregar una
        // huella solo dejaría al conductor sin acceso sin ganar seguridad.
        useDeviceCredentials: true,
        setInvalidatedByBiometricEnrollment: false,
        requireAuthentication: true,
      ),
    );
    if (r.code == BiometricError.success && (r.publicKey ?? '').isNotEmpty) {
      return ResultadoFirma.exito(r.publicKey!);
    }
    AppLogger.warning('Llave del aparato: no se creó',
        context: {'codigo': '${r.code}'});
    return ResultadoFirma.fallo(_mensaje(r.code));
  }

  @override
  Future<ResultadoFirma> firmar(Uint8List mensaje) async {
    final r = await _plugin.createSignatureFromBytes(
      payload: mensaje,
      keyAlias: AppConfig.llaveAlias,
      signatureFormat: SignatureFormat.base64,
      promptMessage: 'Confirma tu identidad para ingresar',
      config: CreateSignatureConfig(allowDeviceCredentials: true),
    );
    if (r.code == BiometricError.success && (r.signature ?? '').isNotEmpty) {
      return ResultadoFirma.exito(r.signature!);
    }
    AppLogger.warning('Llave del aparato: no se firmó',
        context: {'codigo': '${r.code}'});
    return ResultadoFirma.fallo(_mensaje(r.code));
  }

  @override
  Future<void> borrarLlave() async {
    await _plugin.deleteKeys(keyAlias: AppConfig.llaveAlias);
  }

  /// Traduce el código del plugin a un mensaje para la persona. Los códigos
  /// no listados caen en un mensaje general: no se muestran textos técnicos.
  String _mensaje(BiometricError? codigo) {
    switch (codigo) {
      case BiometricError.userCanceled:
        return 'Cancelaste la verificación';
      case BiometricError.notEnrolled:
      case BiometricError.notAvailable:
        return 'Configura una huella, rostro o PIN en tu teléfono para continuar';
      case BiometricError.lockedOut:
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo';
      case BiometricError.lockedOutPermanent:
        return 'Verificación bloqueada. Desbloquea el teléfono con tu PIN';
      case BiometricError.keyInvalidated:
        return 'La llave de este teléfono ya no es válida. '
            'Pide a tu administrador que la restablezca';
      default:
        return 'No se pudo verificar tu identidad en este teléfono';
    }
  }
}
