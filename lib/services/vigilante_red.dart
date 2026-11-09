import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'log_service.dart';

/// Avisa cuando el teléfono recupera la red, para reconectar el WebSocket al instante en vez de
/// esperar el siguiente reintento. Solo la demostración lo usa.
class VigilanteRed {
  final Future<void> Function() alRecuperarRed;
  final Stream<List<ConnectivityResult>> _cambios;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// [cambios] permite probarlo sin plugin; por defecto escucha el estado real de la red.
  VigilanteRed({
    required this.alRecuperarRed,
    Stream<List<ConnectivityResult>>? cambios,
  }) : _cambios = cambios ?? Connectivity().onConnectivityChanged;

  void iniciar() {
    _sub = _cambios.listen((estados) {
      final hayRed = estados.any((e) => e != ConnectivityResult.none);
      // Con red (vuelve la señal o cambia de wifi a datos): se reconecta ya. Si el canal sigue
      // vivo, `reconectarAhora` no hace nada.
      if (hayRed) unawaited(_avisar());
    }, onError: (Object e) {
      AppLogger.warning('VigilanteRed: error', context: {'error': '$e'});
    });
  }

  Future<void> _avisar() async {
    try {
      await alRecuperarRed();
    } on Object catch (e) {
      AppLogger.warning('VigilanteRed: reconexión fallida',
          context: {'error': '$e'});
    }
  }

  void dispose() => _sub?.cancel();
}
