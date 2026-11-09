import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/textos_demo_alertas.dart';
import '../config/theme.dart';
import '../models/alerta_ruta.dart';
import '../services/gestor_alerta_ruta.dart';

/// Textos del aviso de tramo prohibido (centralizados para aprobación).
class TextosViaje {
  TextosViaje._();

  static const String tramoProhibido = TextosAlertaRuta.textoPorDefecto;
  static const String tituloTramoProhibido = 'Tramo prohibido';
  static const String rutaPermitida = TextosAlertaRuta.notificacionRuta;
  static const String entendido = 'Entendido';
}

/// Contenedor del gestor de la alerta de ruta (null en la app de operación). Existe porque
/// `provider` no deja publicar un `ChangeNotifier` anulable directamente.
class AlertasDemo {
  final GestorAlertaRuta? gestor;
  const AlertasDemo(this.gestor);
}

/// El gestor de la alerta de ruta, o null si no hay (app de operación y pruebas sin él).
GestorAlertaRuta? gestorAlertaRutaDe(BuildContext context) {
  try {
    return context.read<AlertasDemo>().gestor;
  } on ProviderNotFoundException {
    return null;
  }
}

/// Diálogo del aviso de tramo prohibido: texto breve y un botón «Entendido».
Future<void> mostrarDialogoTramoProhibido(
  BuildContext context, {
  required String mensaje,
  String? alternativa,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('alerta_tramo_prohibido'),
      backgroundColor: AppTheme.surface,
      icon: const Icon(Icons.warning_amber, color: AppTheme.error, size: 40),
      title: const Text(TextosViaje.tituloTramoProhibido),
      content: Text(
        alternativa == null || mensaje.contains(alternativa)
            ? mensaje
            : '$mensaje\n\n${TextosViaje.rutaPermitida}: $alternativa',
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(TextosViaje.entendido),
        ),
      ],
    ),
  );
}

/// Pregunta breve de sí/no con un texto de explicación (permisos).
Future<bool> confirmarConExplicacion(
  BuildContext context, {
  required String titulo,
  required String explicacion,
  required String si,
  required String no,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      key: const Key('dialogo_permiso'),
      backgroundColor: AppTheme.surface,
      title: Text(titulo),
      content: Text(explicacion),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(no),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(si),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Atajo para mostrar una [AlertaRuta].
Future<void> mostrarAlertaRuta(BuildContext context, AlertaRuta alerta) =>
    mostrarDialogoTramoProhibido(context,
        mensaje: alerta.mensaje, alternativa: alerta.alternativa);
