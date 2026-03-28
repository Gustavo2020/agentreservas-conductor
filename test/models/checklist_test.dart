import 'package:agentreservas_conductor/models/checklist.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _checklistBase({
  String? fotoLlantas,
  String? fotoEquipo,
  String? fotoAceite,
  String? fotoFrenos,
  String? fotoRefri,
}) =>
    {
      'id': 1,
      'estado': 'PENDIENTE',
      'foto_llantas': fotoLlantas,
      'lat_llantas': fotoLlantas != null ? 4.6097 : null,
      'lng_llantas': fotoLlantas != null ? -74.0817 : null,
      'comentario_llantas': null,
      'foto_equipo_carreteras': fotoEquipo,
      'lat_equipo_carreteras': null,
      'lng_equipo_carreteras': null,
      'comentario_equipo_carreteras': null,
      'foto_aceite': fotoAceite,
      'lat_aceite': null,
      'lng_aceite': null,
      'comentario_aceite': null,
      'foto_liquido_frenos': fotoFrenos,
      'lat_liquido_frenos': null,
      'lng_liquido_frenos': null,
      'comentario_liquido_frenos': null,
      'foto_refrigerante': fotoRefri,
      'lat_refrigerante': null,
      'lng_refrigerante': null,
      'comentario_refrigerante': null,
      'mensaje_aprobacion': null,
    };

void main() {
  group('Checklist.fromJson', () {
    test('parsea campos correctamente', () {
      final json = _checklistBase(
        fotoLlantas: 'transportes/T001/checklist/llantas_20260321.jpg',
      );
      final cl = Checklist.fromJson(json);

      expect(cl.id, 1);
      expect(cl.estado, 'PENDIENTE');
      expect(cl.llantas.cargada, isTrue);
      expect(cl.llantas.lat, closeTo(4.6097, 0.0001));
      expect(cl.equipoCarreteras.cargada, isFalse);
    });

    test('completo = false cuando faltan fotos', () {
      final cl = Checklist.fromJson(_checklistBase(fotoLlantas: 'path'));
      expect(cl.completo, isFalse);
    });

    test('completo = true cuando las 5 fotos están cargadas', () {
      final cl = Checklist.fromJson(_checklistBase(
        fotoLlantas: 'a.jpg',
        fotoEquipo: 'b.jpg',
        fotoAceite: 'c.jpg',
        fotoFrenos: 'd.jpg',
        fotoRefri: 'e.jpg',
      ));
      expect(cl.completo, isTrue);
    });

    test('aprobado/rechazado según estado', () {
      final aprobado = Checklist.fromJson({
        ..._checklistBase(),
        'estado': 'APROBADO',
      });
      final rechazado = Checklist.fromJson({
        ..._checklistBase(),
        'estado': 'RECHAZADO',
        'mensaje_aprobacion': 'Foto borrosa',
      });

      expect(aprobado.aprobado, isTrue);
      expect(aprobado.rechazado, isFalse);
      expect(rechazado.rechazado, isTrue);
      expect(rechazado.mensajeAprobacion, 'Foto borrosa');
    });
  });

  group('FotoChecklist.cargada', () {
    test('path null → no cargada', () {
      expect(const FotoChecklist(path: null).cargada, isFalse);
    });

    test('path vacío → no cargada', () {
      expect(const FotoChecklist(path: '').cargada, isFalse);
    });

    test('path no vacío → cargada', () {
      expect(const FotoChecklist(path: 'foto.jpg').cargada, isTrue);
    });
  });
}
