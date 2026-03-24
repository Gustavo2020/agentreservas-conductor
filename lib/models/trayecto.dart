class Trayecto {
  final int id;
  final int diaNumero;
  final String? fecha;
  final String? origenMunicipio;
  final String? origenDireccion;
  final String? destino;
  final String? horaSalida;
  final String? pernoctaMunicipio;

  const Trayecto({
    required this.id,
    required this.diaNumero,
    this.fecha,
    this.origenMunicipio,
    this.origenDireccion,
    this.destino,
    this.horaSalida,
    this.pernoctaMunicipio,
  });

  factory Trayecto.fromJson(Map<String, dynamic> json) {
    return Trayecto(
      id: json['id'] as int,
      diaNumero: json['dia_numero'] as int? ?? 1,
      fecha: json['fecha'] as String?,
      origenMunicipio: json['origen_municipio'] as String?,
      origenDireccion: json['origen_direccion'] as String?,
      destino: json['destino'] as String?,
      horaSalida: json['hora_salida'] as String?,
      pernoctaMunicipio: json['pernocta_municipio'] as String?,
    );
  }
}
