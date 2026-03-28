import 'dart:async';

import 'package:agentreservas_conductor/providers/ws_provider.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:agentreservas_conductor/services/ws_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fake WsService ─────────────────────────────────────────────────────────────

class _FakeWsService extends WsService {
  _FakeWsService(super.auth);

  final _controller = StreamController<WsMensaje>.broadcast();

  @override
  Stream<WsMensaje> get stream => _controller.stream;

  @override
  Future<void> connect(int solicitudId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => false;

  /// Inyecta un mensaje en el stream como si viniera del servidor.
  void injectMessage(WsMensajeTipo tipo, {Map<String, dynamic>? data}) {
    _controller.add(WsMensaje(tipo, data ?? {}));
  }

  void disposeController() => _controller.close();
}

// ── Helpers ────────────────────────────────────────────────────────────────────

WsProvider _buildProvider(_FakeWsService ws) => WsProvider(ws);

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  late _FakeWsService fakeWs;
  late WsProvider provider;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = AuthService(storage: const FlutterSecureStorage());
    fakeWs = _FakeWsService(auth);
    provider = _buildProvider(fakeWs);
  });

  tearDown(() {
    provider.dispose();
    fakeWs.disposeController();
  });

  // ── Estado inicial ─────────────────────────────────────────────────────────

  group('Estado inicial', () {
    test('estado es esperandoInicio', () {
      expect(provider.estado, EstadoViajeActivo.esperandoInicio);
    });

    test('chequeoSolicitado = false', () {
      expect(provider.chequeoSolicitado, false);
    });

    test('enModoPanico = false', () {
      expect(provider.enModoPanico, false);
    });

    test('solicitudCancelada = false', () {
      expect(provider.solicitudCancelada, false);
    });

    test('checklistAprobado = false', () {
      expect(provider.checklistAprobado, false);
    });

    test('viajeConfirmadoPorSolicitante = false', () {
      expect(provider.viajeConfirmadoPorSolicitante, false);
    });
  });

  // ── recuperarEstadoDeViaje ─────────────────────────────────────────────────

  group('recuperarEstadoDeViaje', () {
    test('viajeIniciado=true → estado enRuta', () {
      provider.recuperarEstadoDeViaje(viajeIniciado: true, enSitio: false);
      expect(provider.estado, EstadoViajeActivo.enRuta);
    });

    test('enSitio=true sin viajeIniciado → esperandoConfirmacionUsuario', () {
      provider.recuperarEstadoDeViaje(viajeIniciado: false, enSitio: true);
      expect(provider.estado, EstadoViajeActivo.esperandoConfirmacionUsuario);
    });

    test('ambos false → sin cambio (queda esperandoInicio)', () {
      provider.recuperarEstadoDeViaje(viajeIniciado: false, enSitio: false);
      expect(provider.estado, EstadoViajeActivo.esperandoInicio);
    });

    test('viajeIniciado=true tiene precedencia sobre enSitio=true', () {
      provider.recuperarEstadoDeViaje(viajeIniciado: true, enSitio: true);
      expect(provider.estado, EstadoViajeActivo.enRuta);
    });

    test('si ya está enRuta, viajeIniciado=false no sobreescribe', () {
      provider.marcarViajeIniciado();
      provider.recuperarEstadoDeViaje(viajeIniciado: false, enSitio: false);
      expect(provider.estado, EstadoViajeActivo.enRuta);
    });

    test('si ya está esperandoConfirmacion, viajeIniciado=true NO sobreescribe',
        () {
      provider.marcarEnSitio();
      provider.recuperarEstadoDeViaje(viajeIniciado: true, enSitio: false);
      expect(provider.estado, EstadoViajeActivo.esperandoConfirmacionUsuario);
    });
  });

  // ── Transiciones de estado ─────────────────────────────────────────────────

  group('Transiciones de estado', () {
    test('marcarEnSitio → esperandoConfirmacionUsuario', () {
      provider.marcarEnSitio();
      expect(provider.estado, EstadoViajeActivo.esperandoConfirmacionUsuario);
    });

    test('marcarViajeIniciado → enRuta', () {
      provider.marcarViajeIniciado();
      expect(provider.estado, EstadoViajeActivo.enRuta);
    });

    test('activarModoPanico → modoPanico + enModoPanico=true', () {
      provider.activarModoPanico();
      expect(provider.estado, EstadoViajeActivo.modoPanico);
      expect(provider.enModoPanico, true);
    });

    test('desactivarModoPanico → enRuta', () {
      provider.activarModoPanico();
      provider.desactivarModoPanico();
      expect(provider.estado, EstadoViajeActivo.enRuta);
      expect(provider.enModoPanico, false);
    });
  });

  // ── Mensajes WebSocket ─────────────────────────────────────────────────────

  group('Mensajes WebSocket', () {
    Future<void> conectar() async {
      await provider.conectar(1);
    }

    test('chequeoRequest → chequeoSolicitado=true', () async {
      await conectar();
      expect(provider.chequeoSolicitado, false);
      fakeWs.injectMessage(WsMensajeTipo.chequeoRequest);
      await Future.delayed(Duration.zero);
      expect(provider.chequeoSolicitado, true);
    });

    test('resolverChequeo limpia chequeoSolicitado', () async {
      await conectar();
      fakeWs.injectMessage(WsMensajeTipo.chequeoRequest);
      await Future.delayed(Duration.zero);
      provider.resolverChequeo();
      expect(provider.chequeoSolicitado, false);
    });

    test('solicitudCancelada → solicitudCancelada=true con mensaje', () async {
      await conectar();
      fakeWs.injectMessage(
        WsMensajeTipo.solicitudCancelada,
        data: {'mensaje': 'Cancelado por el usuario'},
      );
      await Future.delayed(Duration.zero);
      expect(provider.solicitudCancelada, true);
      expect(provider.mensajeCancelacion, 'Cancelado por el usuario');
    });

    test('solicitudCancelada sin mensaje usa texto por defecto', () async {
      await conectar();
      fakeWs.injectMessage(WsMensajeTipo.solicitudCancelada, data: {});
      await Future.delayed(Duration.zero);
      expect(provider.mensajeCancelacion, 'El viaje ha sido cancelado.');
    });

    test('limpiarCancelacion resetea flags', () async {
      await conectar();
      fakeWs.injectMessage(WsMensajeTipo.solicitudCancelada, data: {});
      await Future.delayed(Duration.zero);
      provider.limpiarCancelacion();
      expect(provider.solicitudCancelada, false);
      expect(provider.mensajeCancelacion, null);
    });

    test('aprobacionChecklist → checklistAprobado=true', () async {
      await conectar();
      fakeWs.injectMessage(
        WsMensajeTipo.aprobacionChecklist,
        data: {'mensaje': 'Aprobado por el responsable'},
      );
      await Future.delayed(Duration.zero);
      expect(provider.checklistAprobado, true);
      expect(
          provider.mensajeChecklistAprobacion, 'Aprobado por el responsable');
    });

    test('limpiarChecklistAprobado resetea flags', () async {
      await conectar();
      fakeWs.injectMessage(WsMensajeTipo.aprobacionChecklist, data: {});
      await Future.delayed(Duration.zero);
      provider.limpiarChecklistAprobado();
      expect(provider.checklistAprobado, false);
      expect(provider.mensajeChecklistAprobacion, null);
    });

    // ── Flujo VIAJE_CONFIRMADO (nuevo comportamiento) ───────────────────────

    test(
        'viajeConfirmado desde esperandoConfirmacion → viajeConfirmadoPorSolicitante=true',
        () async {
      await conectar();
      provider.marcarEnSitio(); // pasa a esperandoConfirmacionUsuario
      expect(provider.estado, EstadoViajeActivo.esperandoConfirmacionUsuario);

      fakeWs.injectMessage(WsMensajeTipo.viajeConfirmado);
      await Future.delayed(Duration.zero);

      // NO transiciona a viajeConfirmado — activa el flag para auto-iniciar
      expect(provider.viajeConfirmadoPorSolicitante, true);
      // Estado permanece esperandoConfirmacionUsuario hasta que el screen llame iniciarViaje
      expect(provider.estado, EstadoViajeActivo.esperandoConfirmacionUsuario);
    });

    test('viajeConfirmado desde esperandoInicio es ignorado (mensaje encolado)',
        () async {
      await conectar();
      // NO llamamos marcarEnSitio → estado = esperandoInicio
      fakeWs.injectMessage(WsMensajeTipo.viajeConfirmado);
      await Future.delayed(Duration.zero);

      // Mensaje ignorado: aún no se reportó en sitio
      expect(provider.viajeConfirmadoPorSolicitante, false);
      expect(provider.estado, EstadoViajeActivo.esperandoInicio);
    });

    test('viajeConfirmado desde enRuta es ignorado', () async {
      await conectar();
      provider.marcarViajeIniciado(); // ya está en ruta
      fakeWs.injectMessage(WsMensajeTipo.viajeConfirmado);
      await Future.delayed(Duration.zero);

      expect(provider.viajeConfirmadoPorSolicitante, false);
      expect(provider.estado, EstadoViajeActivo.enRuta);
    });

    test('limpiarViajeConfirmado resetea el flag', () async {
      await conectar();
      provider.marcarEnSitio();
      fakeWs.injectMessage(WsMensajeTipo.viajeConfirmado);
      await Future.delayed(Duration.zero);
      expect(provider.viajeConfirmadoPorSolicitante, true);

      provider.limpiarViajeConfirmado();
      expect(provider.viajeConfirmadoPorSolicitante, false);
    });
  });

  // ── conectar() reinicia estado ─────────────────────────────────────────────

  group('conectar() reinicia estado', () {
    test('reinicia a esperandoInicio aunque estuviera enRuta', () async {
      provider.marcarViajeIniciado();
      expect(provider.estado, EstadoViajeActivo.enRuta);

      await provider.conectar(1);
      expect(provider.estado, EstadoViajeActivo.esperandoInicio);
    });

    test('reinicia viajeConfirmadoPorSolicitante', () async {
      provider.marcarEnSitio();
      // Simular que el flag estaba activo
      provider
          .marcarEnSitio(); // Re-marcar (estado ya en esperandoConfirmacion)
      await provider.conectar(1);
      expect(provider.viajeConfirmadoPorSolicitante, false);
    });

    test('reinicia chequeoSolicitado', () async {
      await provider.conectar(1);
      fakeWs.injectMessage(WsMensajeTipo.chequeoRequest);
      await Future.delayed(Duration.zero);
      expect(provider.chequeoSolicitado, true);

      await provider.conectar(1);
      expect(provider.chequeoSolicitado, false);
    });
  });

  // ── esperandoFinalizacion ──────────────────────────────────────────────────

  group('esperandoFinalizacion', () {
    test('marcarEsperandoFinalizacion → estado esperandoFinalizacion', () {
      provider.marcarViajeIniciado();
      provider.marcarEsperandoFinalizacion();
      expect(provider.estado, EstadoViajeActivo.esperandoFinalizacion);
    });

    test('marcarEsperandoFinalizacion es idempotente', () {
      provider.marcarEsperandoFinalizacion();
      provider.marcarEsperandoFinalizacion();
      expect(provider.estado, EstadoViajeActivo.esperandoFinalizacion);
    });
  });

  // ── viajeTerminado WS ──────────────────────────────────────────────────────

  group('viajeTerminado', () {
    test('viajeTerminado inicial = false', () {
      expect(provider.viajeTerminado, false);
    });

    test('mensaje VIAJE_FINALIZADO → viajeTerminado=true', () async {
      await provider.conectar(1);
      fakeWs.injectMessage(WsMensajeTipo.viajeTerminado);
      await Future.delayed(Duration.zero);
      expect(provider.viajeTerminado, true);
    });

    test('limpiarViajeTerminado resetea el flag', () async {
      await provider.conectar(1);
      fakeWs.injectMessage(WsMensajeTipo.viajeTerminado);
      await Future.delayed(Duration.zero);
      provider.limpiarViajeTerminado();
      expect(provider.viajeTerminado, false);
    });

    test('conectar() reinicia viajeTerminado', () async {
      await provider.conectar(1);
      fakeWs.injectMessage(WsMensajeTipo.viajeTerminado);
      await Future.delayed(Duration.zero);
      expect(provider.viajeTerminado, true);
      await provider.conectar(1);
      expect(provider.viajeTerminado, false);
    });
  });

  // ── WsMensajeTipo cobertura ────────────────────────────────────────────────

  group('WsMensajeTipo', () {
    test('todos los tipos del protocolo están definidos', () {
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.chequeoRequest));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.viajeConfirmado));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.aprobacionChecklist));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.aprobacionSoporte));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.solicitudCancelada));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.viajeTerminado));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.notificacion));
      expect(WsMensajeTipo.values, contains(WsMensajeTipo.desconocido));
    });

    test('EstadoViajeActivo — todos los estados tienen índices únicos', () {
      final indices = EstadoViajeActivo.values.map((e) => e.index).toSet();
      expect(indices.length, EstadoViajeActivo.values.length);
    });
  });
}
