import 'package:agentreservas_conductor/models/soporte.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Soporte.fromJson', () {
    final baseJson = {
      'id': 5,
      'solicitud_viaje_id': 10,
      'dia_numero': 2,
      'tipo': 'PEAJE',
      'monto': 15000.0,
      'foto_soporte': 'transportes/T001/soportes/dia2_PEAJE.jpg',
      'estado': 'PENDIENTE',
      'mensaje_rechazo': null,
      'created_at': '2026-03-21T10:30:00',
    };

    test('parsea todos los campos correctamente', () {
      final s = Soporte.fromJson(baseJson);

      expect(s.id, 5);
      expect(s.solicitudViajeId, 10);
      expect(s.diaNumero, 2);
      expect(s.tipo, 'PEAJE');
      expect(s.monto, 15000.0);
      expect(s.estado, 'PENDIENTE');
      expect(s.createdAt, isNotNull);
    });

    test('monto como int se convierte a double', () {
      final json = {...baseJson, 'monto': 8000};
      final s = Soporte.fromJson(json);
      expect(s.monto, 8000.0);
      expect(s.monto, isA<double>());
    });

    test('pendiente/aprobado/rechazado son mutuamente excluyentes', () {
      final pendiente = Soporte.fromJson({...baseJson, 'estado': 'PENDIENTE'});
      final aprobado = Soporte.fromJson({...baseJson, 'estado': 'APROBADO'});
      final rechazado = Soporte.fromJson({...baseJson, 'estado': 'RECHAZADO'});

      expect(pendiente.pendiente, isTrue);
      expect(pendiente.aprobado, isFalse);
      expect(pendiente.rechazado, isFalse);

      expect(aprobado.aprobado, isTrue);
      expect(aprobado.pendiente, isFalse);

      expect(rechazado.rechazado, isTrue);
      expect(rechazado.aprobado, isFalse);
    });

    test('created_at nulo no lanza excepción', () {
      final json = {...baseJson, 'created_at': null};
      final s = Soporte.fromJson(json);
      expect(s.createdAt, isNull);
    });

    test('tipos de soporte válidos', () {
      for (final tipo in ['PEAJE', 'PARQUEADERO', 'LAVADO']) {
        final s = Soporte.fromJson({...baseJson, 'tipo': tipo});
        expect(s.tipo, tipo);
      }
    });
  });
}
