import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../services/log_service.dart';

/// Resultado de captura de foto con geolocalización obligatoria.
class FotoGeoResult {
  final Uint8List bytes;
  final String filename;
  final double lat;
  final double lng;

  const FotoGeoResult({
    required this.bytes,
    required this.filename,
    required this.lat,
    required this.lng,
  });
}

/// Widget que encapsula cámara + GPS obligatorio.
/// Las fotos se capturan SOLO con la cámara (no galería).
/// No se guardan en la galería del dispositivo.
class FotoGeolocalizadaWidget extends StatefulWidget {
  final String? fotoPath;
  final double? lat;
  final double? lng;
  final String etiqueta;
  final String campoFoto;
  final Future<void> Function(FotoGeoResult result, String? comentario)
      onFotoCapturada;

  const FotoGeolocalizadaWidget({
    super.key,
    required this.etiqueta,
    required this.campoFoto,
    required this.onFotoCapturada,
    this.fotoPath,
    this.lat,
    this.lng,
  });

  @override
  State<FotoGeolocalizadaWidget> createState() =>
      _FotoGeolocalizadaWidgetState();
}

class _FotoGeolocalizadaWidgetState extends State<FotoGeolocalizadaWidget> {
  final _comentarioCtrl = TextEditingController();
  bool _capturando = false;
  String? _error;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    setState(() {
      _capturando = true;
      _error = null;
    });

    try {
      // 1. Permiso de cámara
      final camPerm = ImagePicker().supportsImageSource(ImageSource.camera);
      if (!camPerm) {
        setState(() => _error = 'La cámara no está disponible');
        return;
      }

      // 2. Permiso de ubicación
      var locPerm = await Geolocator.checkPermission();
      if (locPerm == LocationPermission.denied) {
        locPerm = await Geolocator.requestPermission();
      }
      if (locPerm == LocationPermission.denied ||
          locPerm == LocationPermission.deniedForever) {
        setState(() => _error = 'Se requieren permisos de ubicación');
        return;
      }

      // 3. GPS activo
      final gpsActivo = await Geolocator.isLocationServiceEnabled();
      if (!gpsActivo) {
        setState(() => _error = 'Se requiere GPS activo');
        return;
      }

      // 4. Obtener posición
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;

      // 5. Capturar foto SOLO con cámara
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (xFile == null || !mounted) return;

      final bytes = await xFile.readAsBytes();
      final filename =
          '${widget.campoFoto}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await widget.onFotoCapturada(
        FotoGeoResult(
          bytes: bytes,
          filename: filename,
          lat: pos.latitude,
          lng: pos.longitude,
        ),
        _comentarioCtrl.text.trim().isEmpty ? null : _comentarioCtrl.text.trim(),
      );
    } on Exception catch (e, st) {
      AppLogger.error('FotoGeolocalizadaWidget: error capturando foto',
          e, stackTrace: st,
          context: {'campo': widget.campoFoto});
      if (mounted) setState(() => _error = 'Error capturando foto: $e');
    } finally {
      if (mounted) setState(() => _capturando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneFoto = widget.fotoPath != null && widget.fotoPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Miniatura o botón de captura
        if (tieneFoto) ...[
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: AppTheme.surface,
                  child: const Icon(
                    Icons.check_circle,
                    color: AppTheme.success,
                    size: 48,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '📍 ${widget.lat?.toStringAsFixed(5)}, '
                    '${widget.lng?.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comentarioCtrl,
            decoration: const InputDecoration(
              labelText: 'Comentario (opcional)',
              isDense: true,
            ),
            maxLines: 2,
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _capturando ? null : _tomarFoto,
              icon: _capturando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(_capturando ? 'Capturando...' : '📷 Tomar foto'),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: const TextStyle(color: AppTheme.error, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
