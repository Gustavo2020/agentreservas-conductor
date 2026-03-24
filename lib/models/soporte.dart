class Soporte {
  final int id;
  final int solicitudViajeId;
  final int diaNumero;
  final String tipo; // PEAJE | PARQUEADERO | LAVADO
  final double monto;
  final String fotoSoporte;
  final String estado; // PENDIENTE | APROBADO | RECHAZADO
  final String? mensajeRechazo;
  final DateTime? createdAt;

  const Soporte({
    required this.id,
    required this.solicitudViajeId,
    required this.diaNumero,
    required this.tipo,
    required this.monto,
    required this.fotoSoporte,
    required this.estado,
    this.mensajeRechazo,
    this.createdAt,
  });

  factory Soporte.fromJson(Map<String, dynamic> json) {
    return Soporte(
      id: json['id'] as int,
      solicitudViajeId: json['solicitud_viaje_id'] as int? ?? 0,
      diaNumero: json['dia_numero'] as int? ?? 1,
      tipo: json['tipo'] as String? ?? '',
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
      fotoSoporte: json['foto_soporte'] as String? ?? '',
      estado: json['estado'] as String? ?? 'PENDIENTE',
      mensajeRechazo: json['mensaje_rechazo'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  bool get pendiente => estado == 'PENDIENTE';
  bool get aprobado => estado == 'APROBADO';
  bool get rechazado => estado == 'RECHAZADO';
}
