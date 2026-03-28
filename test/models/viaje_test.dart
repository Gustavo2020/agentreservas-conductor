import 'package:agentreservas_conductor/models/viaje.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Viaje.fromJson', () {
    test('parsea campos básicos correctamente', () {
      final json = {
        'id': 42,
        'token': 'TRP-2026-001',
        'estado': 'APROBADO',
        'solicitante_nombre': 'Juan Pérez',
        'solicitante_email': 'juan@empresa.com',
        'destino_final_municipio': 'Cali, Valle',
        'fecha_solicitud': '2026-03-21T08:00:00',
      };

      final viaje = Viaje.fromJson(json);

      expect(viaje.id, 42);
      expect(viaje.token, 'TRP-2026-001');
      expect(viaje.estado, 'APROBADO');
      expect(viaje.solicitanteNombre, 'Juan Pérez');
      expect(viaje.solicitanteEmail, 'juan@empresa.com');
      expect(viaje.destinoFinalMunicipio, 'Cali, Valle');
      expect(viaje.fechaSolicitud, isNotNull);
    });

    test('maneja campos nulos sin lanzar excepción', () {
      final json = {'id': 1, 'token': 'T-001', 'estado': 'APROBADO'};
      final viaje = Viaje.fromJson(json);

      expect(viaje.solicitanteNombre, isNull);
      expect(viaje.destinoFinalMunicipio, isNull);
      expect(viaje.trayectos, isEmpty);
      expect(viaje.checklist, isNull);
    });

    test('parsea trayectos anidados', () {
      final json = {
        'id': 1,
        'token': 'T-001',
        'estado': 'EN_CURSO',
        'trayectos': [
          {
            'id': 10,
            'dia_numero': 1,
            'origen_municipio': 'Bogotá',
            'destino_municipio': 'Palmira',
            'hora_salida': '07:00',
          }
        ],
      };

      final viaje = Viaje.fromJson(json);

      expect(viaje.trayectos, hasLength(1));
      expect(viaje.trayectos.first.origenMunicipio, 'Bogotá');
    });

    test('fecha_solicitud nula no lanza excepción', () {
      final json = {'id': 1, 'token': 'T', 'estado': 'APROBADO'};
      final viaje = Viaje.fromJson(json);
      expect(viaje.fechaSolicitud, isNull);
    });
  });

  group('Viaje.rutaAceptada', () {
    test('ruta_aceptada=true → rutaAceptada=true', () {
      final v = Viaje.fromJson(
          {'id': 1, 'token': 'T', 'estado': 'APROBADO', 'ruta_aceptada': true});
      expect(v.rutaAceptada, isTrue);
    });

    test('ruta_aceptada=1 (int de DB) → rutaAceptada=true', () {
      final v = Viaje.fromJson(
          {'id': 1, 'token': 'T', 'estado': 'APROBADO', 'ruta_aceptada': 1});
      expect(v.rutaAceptada, isTrue);
    });

    test('ruta_aceptada=false → rutaAceptada=false', () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'APROBADO',
        'ruta_aceptada': false
      });
      expect(v.rutaAceptada, isFalse);
    });

    test('ruta_aceptada ausente → rutaAceptada=false (default)', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'APROBADO'});
      expect(v.rutaAceptada, isFalse);
    });
  });

  group('Viaje.viajeIniciado / enSitio', () {
    test('viaje_iniciado=true → viajeIniciado=true', () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'viaje_iniciado': true
      });
      expect(v.viajeIniciado, isTrue);
    });

    test('viaje_iniciado=1 (int DB) → viajeIniciado=true', () {
      final v = Viaje.fromJson(
          {'id': 1, 'token': 'T', 'estado': 'EN_CURSO', 'viaje_iniciado': 1});
      expect(v.viajeIniciado, isTrue);
    });

    test('viaje_iniciado ausente → viajeIniciado=false (default)', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'EN_CURSO'});
      expect(v.viajeIniciado, isFalse);
    });

    test('en_sitio=true → enSitio=true', () {
      final v = Viaje.fromJson(
          {'id': 1, 'token': 'T', 'estado': 'APROBADO', 'en_sitio': true});
      expect(v.enSitio, isTrue);
    });

    test('en_sitio ausente → enSitio=false (default)', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'APROBADO'});
      expect(v.enSitio, isFalse);
    });

    test(
        'estado EN_CURSO sin viaje_iniciado → viajeIniciado=false (bug histórico)',
        () {
      // El backend setea EN_CURSO al asignar vehículo; no implica que el
      // conductor haya iniciado el viaje. viajeIniciado es el campo correcto.
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'EN_CURSO'});
      expect(v.esEnCurso, isTrue); // estado DB = EN_CURSO
      expect(v.viajeIniciado, isFalse); // pero aún no inició formalmente
    });
  });

  group('Viaje.totalDias / todosLosDiasCerrados', () {
    test('sin trayectos → totalDias=1', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'EN_CURSO'});
      expect(v.totalDias, 1);
    });

    test('trayectos dias 1 y 2 → totalDias=2', () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'trayectos': [
          {
            'id': 1,
            'dia_numero': 1,
            'origen_municipio': 'Bogotá',
            'destino_municipio': 'Cali'
          },
          {
            'id': 2,
            'dia_numero': 2,
            'origen_municipio': 'Cali',
            'destino_municipio': 'Palmira'
          },
        ],
      });
      expect(v.totalDias, 2);
    });

    test('ningún día cerrado → todosLosDiasCerrados=false', () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'trayectos': [
          {
            'id': 1,
            'dia_numero': 1,
            'origen_municipio': 'A',
            'destino_municipio': 'B'
          },
          {
            'id': 2,
            'dia_numero': 2,
            'origen_municipio': 'B',
            'destino_municipio': 'C'
          },
        ],
      });
      expect(v.todosLosDiasCerrados, isFalse);
    });

    test('solo día 1 cerrado en viaje de 2 días → todosLosDiasCerrados=false',
        () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'trayectos': [
          {
            'id': 1,
            'dia_numero': 1,
            'origen_municipio': 'A',
            'destino_municipio': 'B'
          },
          {
            'id': 2,
            'dia_numero': 2,
            'origen_municipio': 'B',
            'destino_municipio': 'C'
          },
        ],
        'cierres': [
          {'dia_numero': 1, 'solicitud_viaje_id': 1}
        ],
      });
      expect(v.todosLosDiasCerrados, isFalse);
      expect(v.diaActual, 2);
    });

    test('ambos días cerrados en viaje de 2 días → todosLosDiasCerrados=true',
        () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'trayectos': [
          {
            'id': 1,
            'dia_numero': 1,
            'origen_municipio': 'A',
            'destino_municipio': 'B'
          },
          {
            'id': 2,
            'dia_numero': 2,
            'origen_municipio': 'B',
            'destino_municipio': 'C'
          },
        ],
        'cierres': [
          {'dia_numero': 1, 'solicitud_viaje_id': 1},
          {'dia_numero': 2, 'solicitud_viaje_id': 1},
        ],
      });
      expect(v.todosLosDiasCerrados, isTrue);
      expect(v.diaActual, 3);
    });
  });

  group('Viaje.diasCerrados / diaActual', () {
    test('sin cierres → diasCerrados vacío y diaActual=1', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'EN_CURSO'});
      expect(v.diasCerrados, isEmpty);
      expect(v.diaActual, 1);
    });

    test('cierres=[{dia_numero:1}] → diaActual=2', () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'cierres': [
          {'dia_numero': 1, 'solicitud_viaje_id': 1}
        ],
      });
      expect(v.diasCerrados, [1]);
      expect(v.diaActual, 2);
    });

    test('cierres=[{dia_numero:1},{dia_numero:2}] → diaActual=3', () {
      final v = Viaje.fromJson({
        'id': 1,
        'token': 'T',
        'estado': 'EN_CURSO',
        'cierres': [
          {'dia_numero': 1, 'solicitud_viaje_id': 1},
          {'dia_numero': 2, 'solicitud_viaje_id': 1},
        ],
      });
      expect(v.diasCerrados, [1, 2]);
      expect(v.diaActual, 3);
    });

    test('cierres=null → diaActual=1', () {
      final v = Viaje.fromJson(
          {'id': 1, 'token': 'T', 'estado': 'EN_CURSO', 'cierres': null});
      expect(v.diaActual, 1);
    });
  });

  group('Viaje.esProximo / esEnCurso', () {
    test('estado APROBADO → esProximo=true, esEnCurso=false', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'APROBADO'});
      expect(v.esProximo, isTrue);
      expect(v.esEnCurso, isFalse);
    });

    test('estado EN_CURSO → esEnCurso=true, esProximo=false', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'EN_CURSO'});
      expect(v.esEnCurso, isTrue);
      expect(v.esProximo, isFalse);
    });

    test('estado FINALIZADO → ambos false', () {
      final v = Viaje.fromJson({'id': 1, 'token': 'T', 'estado': 'FINALIZADO'});
      expect(v.esProximo, isFalse);
      expect(v.esEnCurso, isFalse);
    });
  });
}
