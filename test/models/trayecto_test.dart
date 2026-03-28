import 'package:agentreservas_conductor/models/trayecto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Trayecto.fromJson', () {
    test('parsea todos los campos', () {
      final json = {
        'id': 3,
        'dia_numero': 1,
        'origen_municipio': 'Bogotá, Cundinamarca',
        'destino': 'Palmira, Valle',
        'hora_salida': '07:00',
        'pernocta_municipio': 'Cali',
      };
      final t = Trayecto.fromJson(json);

      expect(t.id, 3);
      expect(t.diaNumero, 1);
      expect(t.origenMunicipio, 'Bogotá, Cundinamarca');
      expect(t.destino, 'Palmira, Valle');
      expect(t.horaSalida, '07:00');
      expect(t.pernoctaMunicipio, 'Cali');
    });

    test('día por defecto es 1 cuando no viene en JSON', () {
      final t = Trayecto.fromJson({'id': 1});
      expect(t.diaNumero, 1);
    });

    test('campos opcionales nulos no lanzan excepción', () {
      final t = Trayecto.fromJson({'id': 2, 'dia_numero': 2});
      expect(t.origenMunicipio, isNull);
      expect(t.destino, isNull);
      expect(t.pernoctaMunicipio, isNull);
    });
  });
}
