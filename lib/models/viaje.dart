import 'checklist.dart';
import 'trayecto.dart';

class Viajero {
  final String nombre;
  final bool esSolicitante;

  const Viajero({required this.nombre, this.esSolicitante = false});

  factory Viajero.fromJson(Map<String, dynamic> json) {
    final nombre = (json['nombre_usuario'] as String?) ??
        (json['nombre_externo'] as String?) ??
        (json['email_usuario'] as String?) ??
        (json['email_externo'] as String?) ??
        '—';
    return Viajero(
      nombre: nombre,
      esSolicitante:
          json['es_solicitante'] == 1 || json['es_solicitante'] == true,
    );
  }
}

class Viaje {
  final int id;
  final String token;
  final String estado;
  final String? solicitanteNombre;
  final String? solicitanteEmail;
  final String? destinoFinalMunicipio;
  final DateTime? fechaSolicitud;
  final List<Trayecto> trayectos;
  final Checklist? checklist;
  final List<Viajero> viajeros;
  final bool rutaAceptada;

  /// true si existe el evento VIAJE_INICIADO en trazabilidad.
  /// Usar ESTE campo (no `esEnCurso`) para saber si el viaje arrancó,
  /// ya que el backend puede setear EN_CURSO al asignar el vehículo.
  final bool viajeIniciado;

  /// true si existe el evento EN_SITIO_RECOGIDA en trazabilidad.
  final bool enSitio;

  /// Días ya cerrados por el conductor (dia_numero de cierres_dia_viaje).
  final List<int> diasCerrados;

  const Viaje({
    required this.id,
    required this.token,
    required this.estado,
    this.solicitanteNombre,
    this.solicitanteEmail,
    this.destinoFinalMunicipio,
    this.fechaSolicitud,
    this.trayectos = const [],
    this.checklist,
    this.viajeros = const [],
    this.rutaAceptada = false,
    this.viajeIniciado = false,
    this.enSitio = false,
    this.diasCerrados = const [],
  });

  /// Día activo = último día cerrado + 1 (o 1 si aún no se cerró ninguno).
  int get diaActual {
    if (diasCerrados.isEmpty) return 1;
    final maxCerrado = diasCerrados.fold(0, (m, d) => d > m ? d : m);
    return maxCerrado + 1;
  }

  /// Total de días del viaje según los trayectos registrados.
  int get totalDias {
    if (trayectos.isEmpty) return 1;
    return trayectos.fold(1, (m, t) => t.diaNumero > m ? t.diaNumero : m);
  }

  /// true si todos los días del viaje ya fueron cerrados por el conductor.
  bool get todosLosDiasCerrados => diaActual > totalDias;

  factory Viaje.fromJson(Map<String, dynamic> json) {
    return Viaje(
      id: json['id'] as int,
      token: json['token'] as String? ?? '',
      estado: json['estado'] as String? ?? '',
      solicitanteNombre: json['solicitante_nombre'] as String?,
      solicitanteEmail: json['solicitante_email'] as String?,
      destinoFinalMunicipio: json['destino_final_municipio'] as String?,
      fechaSolicitud: json['fecha_solicitud'] != null
          ? DateTime.tryParse(json['fecha_solicitud'] as String)
          : null,
      trayectos: (json['trayectos'] as List<dynamic>?)
              ?.map((t) => Trayecto.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      checklist: json['checklist'] != null
          ? Checklist.fromJson(json['checklist'] as Map<String, dynamic>)
          : null,
      viajeros: (json['viajeros'] as List<dynamic>?)
              ?.map((v) => Viajero.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      rutaAceptada: json['ruta_aceptada'] == true || json['ruta_aceptada'] == 1,
      viajeIniciado:
          json['viaje_iniciado'] == true || json['viaje_iniciado'] == 1,
      enSitio: json['en_sitio'] == true || json['en_sitio'] == 1,
      diasCerrados: (json['cierres'] as List<dynamic>?)
              ?.map((c) => (c as Map<String, dynamic>)['dia_numero'] as int)
              .toList() ??
          const [],
    );
  }

  bool get esProximo => estado == 'APROBADO';
  bool get esEnCurso => estado == 'EN_CURSO';
}
