import 'package:image_picker/image_picker.dart';

import 'log_service.dart';

/// Toma una foto con la cámara. En la APK normal NO hay galería (la evidencia debe ser tomada en
/// el momento). En la demo, si no hay cámara o no se concedió el permiso, se permite elegir de la
/// galería para poder mostrar el flujo en un teléfono sin cámara utilizable.
Future<XFile?> capturarFoto({
  required bool permitirGaleria,
  bool soloGaleria = false,
  ImagePicker? picker,
}) async {
  final p = picker ?? ImagePicker();
  Future<XFile?> galeria() => p.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
  if (soloGaleria && permitirGaleria) return galeria();
  try {
    if (!p.supportsImageSource(ImageSource.camera)) {
      if (permitirGaleria) return galeria();
      throw StateError('La cámara no está disponible');
    }
    return await p.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
  } on Exception catch (e) {
    if (!permitirGaleria) rethrow;
    AppLogger.warning('Foto: cámara no disponible, se usa la galería (demo)',
        context: {'error': '$e'});
    return galeria();
  }
}
