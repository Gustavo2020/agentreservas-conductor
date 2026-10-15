import 'dart:convert';
import 'dart:typed_data';

import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_firma.dart';
import '../helpers/servidor_falso.dart';

/// Crea un AuthService con storage en memoria (sin Keystore real), un
/// MockClient HTTP y una llave de aparato falsa.
AuthService _makeService({
  required Future<http.Response> Function(http.Request) handler,
  Map<String, String> initialStorage = const {},
  FakeFirmaDispositivo? firma,
}) {
  FlutterSecureStorage.setMockInitialValues(Map.from(initialStorage));

  return AuthService(
    httpClient: MockClient(handler),
    storage: const FlutterSecureStorage(),
    firma: firma ?? FakeFirmaDispositivo(),
  );
}

void main() {
  group('primer login: enrolar el aparato', () {
    test(
        'la clave no da sesión: se enrola la llave y recién entonces hay token',
        () async {
      final servidor = ServidorFalso(token: 'JWT', nombre: 'Juan Conductor');
      final firma = FakeFirmaDispositivo(llavePublica: 'PUB');
      final service = _makeService(handler: servidor.manejar, firma: firma);

      final result = await service.login('juan@geb.com', 'password123');

      expect(result.success, isTrue);
      expect(result.token, 'JWT');
      expect(result.userData?['nombre'], 'Juan Conductor');
      expect(await service.getToken(), 'JWT');
      expect(servidor.rutas, [
        '/api/auth/conductor-login',
        '/api/auth/conductor-enrolar',
      ]);
      final enrolar = servidor.recibidos['/api/auth/conductor-enrolar']!;
      expect(enrolar['session'], 'PRE');
      expect(enrolar['llave_publica'], 'PUB');
      expect((enrolar['nombre'] as String).isNotEmpty, isTrue);
      expect(firma.llamadasCrear, 1);
    });

    test('guarda el identificador del aparato para los siguientes ingresos',
        () async {
      final servidor = ServidorFalso(dispositivoId: 11);
      final service = _makeService(handler: servidor.manejar);

      await service.login('juan@geb.com', 'pass');

      expect(await service.getDispositivoId(), 11);
    });

    test('si había una llave local vieja (reinstalación) la reemplaza',
        () async {
      final firma = FakeFirmaDispositivo(existe: true);
      final service =
          _makeService(handler: ServidorFalso().manejar, firma: firma);

      final result = await service.login('juan@geb.com', 'pass');

      expect(result.success, isTrue);
      expect(firma.llamadasBorrar, 1);
      expect(firma.llamadasCrear, 1);
    });

    test('si el usuario cancela la verificación no se llama a enrolar',
        () async {
      final servidor = ServidorFalso();
      final firma =
          FakeFirmaDispositivo(errorCrear: 'Cancelaste la verificación');
      final service = _makeService(handler: servidor.manejar, firma: firma);

      final result = await service.login('juan@geb.com', 'pass');

      expect(result.success, isFalse);
      expect(result.error, 'Cancelaste la verificación');
      expect(servidor.rutas, ['/api/auth/conductor-login']);
      expect(await service.isLoggedIn(), isFalse);
    });
  });

  group('siguientes ingresos: firmar el reto', () {
    test('envía el aparato conocido y firma dominio + reto con la llave',
        () async {
      final servidor = ServidorFalso(token: 'JWT2', dispositivoId: 7)
        ..aparatoEnrolado = true;
      final firma = FakeFirmaDispositivo(firmaB64: 'SIG', existe: true);
      final service = _makeService(
        handler: servidor.manejar,
        initialStorage: {'conductor_dispositivo_id': '7'},
        firma: firma,
      );

      final result = await service.login('juan@geb.com', 'pass');

      expect(result.success, isTrue);
      expect(result.token, 'JWT2');
      expect(
        servidor.recibidos['/api/auth/conductor-login']!['dispositivo_id'],
        7,
      );
      final firmar = servidor.recibidos['/api/auth/conductor-firmar']!;
      expect(firmar['session'], 'PRE');
      expect(firmar['dispositivo_id'], 7);
      expect(firmar['reto'], servidor.reto);
      expect(firmar['firma'], 'SIG');
      // El mensaje firmado es EXACTAMENTE dominio + bytes del reto.
      final esperado = Uint8List.fromList([
        ...utf8.encode('patrix:conductor:v1:'),
        ...base64Decode(servidor.reto),
      ]);
      expect(firma.ultimoMensaje, esperado);
      expect(firma.llamadasCrear, 0);
    });

    test('si el usuario cancela la firma no se llama a conductor-firmar',
        () async {
      final servidor = ServidorFalso()..aparatoEnrolado = true;
      final firma =
          FakeFirmaDispositivo(errorFirmar: 'Cancelaste la verificación');
      final service = _makeService(
        handler: servidor.manejar,
        initialStorage: {'conductor_dispositivo_id': '7'},
        firma: firma,
      );

      final result = await service.login('juan@geb.com', 'pass');

      expect(result.success, isFalse);
      expect(result.error, 'Cancelaste la verificación');
      expect(servidor.rutas, ['/api/auth/conductor-login']);
    });

    test('firma rechazada por el servidor: mensaje de verificación', () async {
      final service = _makeService(
        handler: (r) async {
          if (r.url.path.endsWith('conductor-login')) {
            return respuestaJson({
              'step': 'firmar',
              'session': 'PRE',
              'dispositivo_id': 7,
              'reto': 'AAAA',
            });
          }
          return respuestaJson({'detail': 'Credenciales incorrectas'}, 401);
        },
        initialStorage: {'conductor_dispositivo_id': '7'},
      );

      final result = await service.login('juan@geb.com', 'pass');

      expect(result.success, isFalse);
      expect(result.error, contains('verificar'));
      expect(await service.isLoggedIn(), isFalse);
    });
  });

  group('errores del primer paso', () {
    test('401 retorna "Credenciales incorrectas"', () async {
      final service = _makeService(
        handler: (_) async => respuestaJson({'detail': 'x'}, 401),
      );
      final result = await service.login('x@geb.com', 'wrong');
      expect(result.success, isFalse);
      expect(result.error, 'Credenciales incorrectas');
    });

    test('403 de cuenta sin permiso muestra el motivo del servidor', () async {
      final service = _makeService(
        handler: (_) async => respuestaJson({
          'detail': 'Esta cuenta no tiene acceso a la app del conductor',
        }, 403),
      );
      final result = await service.login('x@geb.com', 'pass');
      expect(result.success, isFalse);
      expect(result.error, contains('no tiene acceso'));
    });

    test('403 de aparato ajeno se explica y manda al administrador', () async {
      final service = _makeService(
        handler: (_) async => respuestaJson({
          'detail':
              'Este aparato no esta registrado para su cuenta. Pida a su administrador restablecerlo.',
        }, 403),
      );
      final result = await service.login('x@geb.com', 'pass');
      expect(result.success, isFalse);
      expect(result.error, contains('administrador'));
    });

    test('respuesta sin paso reconocible es un error', () async {
      final service = _makeService(
        handler: (_) async => respuestaJson({'nombre': 'sin paso'}),
      );
      final result = await service.login('x@geb.com', 'pass');
      expect(result.success, isFalse);
      expect(result.error, contains('inválida'));
    });

    test('excepción de red retorna error de conexión', () async {
      final service = _makeService(
        handler: (_) async => throw Exception('Connection refused'),
      );
      final result = await service.login('x@geb.com', 'pass');
      expect(result.success, isFalse);
      expect(result.error, contains('Error de conexión'));
    });
  });

  group('AuthService.isLoggedIn / logout', () {
    test('isLoggedIn = false cuando storage vacío', () async {
      final service =
          _makeService(handler: (_) async => http.Response('', 200));
      expect(await service.isLoggedIn(), isFalse);
    });

    test('isLoggedIn = true después de login exitoso', () async {
      final service = _makeService(handler: ServidorFalso().manejar);
      await service.login('x@geb.com', 'pass');
      expect(await service.isLoggedIn(), isTrue);
    });

    test('logout limpia la sesión pero conserva el aparato y su llave',
        () async {
      final firma = FakeFirmaDispositivo();
      final service = _makeService(
        handler: ServidorFalso(dispositivoId: 9).manejar,
        firma: firma,
      );
      await service.login('x@geb.com', 'pass');
      expect(await service.isLoggedIn(), isTrue);

      await service.logout();

      expect(await service.isLoggedIn(), isFalse);
      expect(await service.getToken(), isNull);
      expect(await service.getUserData(), isNull);
      // El aparato sigue enrolado: cerrar sesión no es perder el segundo factor.
      expect(await service.getDispositivoId(), 9);
      expect(firma.llamadasBorrar, 0);
    });
  });

  group('AuthService.getUserData', () {
    test('retorna null cuando no hay datos guardados', () async {
      final service =
          _makeService(handler: (_) async => http.Response('', 200));
      expect(await service.getUserData(), isNull);
    });

    test('retorna datos completos tras login', () async {
      final service = _makeService(
        handler: ServidorFalso(nombre: 'Ana').manejar,
      );
      await service.login('ana@geb.com', 'pass');
      final data = await service.getUserData();
      expect(data?['nombre'], 'Ana');
      expect(data?['conductor_id'], 3);
    });
  });
}
