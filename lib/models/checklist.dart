class FotoChecklist {
  final String? path;
  final double? lat;
  final double? lng;
  final String? comentario;

  const FotoChecklist({this.path, this.lat, this.lng, this.comentario});

  bool get cargada => path != null && path!.isNotEmpty;
}

class Checklist {
  final int id;
  final String estado; // PENDIENTE | APROBADO | RECHAZADO
  final bool enviadoRevision;
  final FotoChecklist llantas;
  final FotoChecklist equipoCarreteras;
  final FotoChecklist aceite;
  final FotoChecklist liquidoFrenos;
  final FotoChecklist refrigerante;
  final String? aprobadoPorNombre;
  final String? mensajeAprobacion;

  const Checklist({
    required this.id,
    required this.estado,
    this.enviadoRevision = false,
    required this.llantas,
    required this.equipoCarreteras,
    required this.aceite,
    required this.liquidoFrenos,
    required this.refrigerante,
    this.aprobadoPorNombre,
    this.mensajeAprobacion,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    return Checklist(
      id: json['id'] as int,
      estado: json['estado'] as String? ?? 'PENDIENTE',
      enviadoRevision:
          (json['enviado_revision'] == true || json['enviado_revision'] == 1),
      llantas: FotoChecklist(
        path: json['foto_llantas'] as String?,
        lat: (json['lat_llantas'] as num?)?.toDouble(),
        lng: (json['lng_llantas'] as num?)?.toDouble(),
        comentario: json['comentario_llantas'] as String?,
      ),
      equipoCarreteras: FotoChecklist(
        path: json['foto_equipo_carreteras'] as String?,
        lat: (json['lat_equipo_carreteras'] as num?)?.toDouble(),
        lng: (json['lng_equipo_carreteras'] as num?)?.toDouble(),
        comentario: json['comentario_equipo_carreteras'] as String?,
      ),
      aceite: FotoChecklist(
        path: json['foto_aceite'] as String?,
        lat: (json['lat_aceite'] as num?)?.toDouble(),
        lng: (json['lng_aceite'] as num?)?.toDouble(),
        comentario: json['comentario_aceite'] as String?,
      ),
      liquidoFrenos: FotoChecklist(
        path: json['foto_liquido_frenos'] as String?,
        lat: (json['lat_liquido_frenos'] as num?)?.toDouble(),
        lng: (json['lng_liquido_frenos'] as num?)?.toDouble(),
        comentario: json['comentario_liquido_frenos'] as String?,
      ),
      refrigerante: FotoChecklist(
        path: json['foto_refrigerante'] as String?,
        lat: (json['lat_refrigerante'] as num?)?.toDouble(),
        lng: (json['lng_refrigerante'] as num?)?.toDouble(),
        comentario: json['comentario_refrigerante'] as String?,
      ),
      aprobadoPorNombre: json['aprobado_por_nombre'] as String?,
      mensajeAprobacion: json['mensaje_aprobacion'] as String?,
    );
  }

  bool get completo =>
      llantas.cargada &&
      equipoCarreteras.cargada &&
      aceite.cargada &&
      liquidoFrenos.cargada &&
      refrigerante.cargada;

  bool get aprobado => estado == 'APROBADO';
  bool get rechazado => estado == 'RECHAZADO';
}
