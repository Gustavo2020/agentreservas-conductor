import 'dart:async';
import 'dart:convert';

import 'package:agentreservas_conductor/models/alerta_ruta.dart';
import 'package:agentreservas_conductor/providers/auth_provider.dart';
import 'package:agentreservas_conductor/providers/viaje_provider.dart';
import 'package:agentreservas_conductor/providers/ws_provider.dart';
import 'package:agentreservas_conductor/screens/puerta_sesion.dart';
import 'package:agentreservas_conductor/services/api_service.dart';
import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:agentreservas_conductor/services/cola_posiciones.dart';
import 'package:agentreservas_conductor/services/gestor_alerta_ruta.dart';
import 'package:agentreservas_conductor/services/notificador_alertas.dart';
import 'package:agentreservas_conductor/services/panico_service.dart';
import 'package:agentreservas_conductor/services/seguimiento_controller.dart';
import 'package:agentreservas_conductor/services/seguimiento_service.dart';
import 'package:agentreservas_conductor/services/servicio_viaje.dart';
import 'package:agentreservas_conductor/services/ubicacion_fuente.dart';
import 'package:agentreservas_conductor/services/ws_service.dart';
import 'package:agentreservas_conductor/widgets/anfitrion_alertas.dart';
import 'package:agentreservas_conductor/widgets/control_sesion.dart';
import 'package:agentreservas_conductor/widgets/dialogo_alerta_ruta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'servidor_falso.dart';

/// JWT sin firma real con el claim `exp` (la app solo lee el vencimiento).
String jwtQueVence(DateTime exp) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'none'})}.${b64({
        'exp': exp.millisecondsSinceEpoch ~/ 1000
      })}.firma';
}

class WsFalso extends WsService {
  WsFalso(super.auth);
  final _c = StreamController<WsMensaje>.broadcast();
  int conexiones = 0;
  int desconexiones = 0;
  int reconexionesInmediatas = 0;

  @override
  Stream<WsMensaje> get stream => _c.stream;
  @override
  Future<void> connect(int solicitudId) async => conexiones++;
  @override
  Future<void> disconnect() async => desconexiones++;
  @override
  Future<void> reconectarAhora() async => reconexionesInmediatas++;

  void emitir(Map<String, dynamic> json) => _c.add(WsMensaje.fromJson(json));
}

class NotificadorFalso implements NotificadorAlertas {
  final List<AlertaRuta> mostradas = [];
  int cancelaciones = 0;
  bool permiso = true;
  int pedidosDePermiso = 0;
  AlertaRuta? lanzamiento;
  void Function(AlertaRuta)? alTocar;

  @override
  Future<void> iniciar({required void Function(AlertaRuta) alTocar}) async =>
      this.alTocar = alTocar;
  @override
  Future<AlertaRuta?> alertaDeLanzamiento() async => lanzamiento;
  @override
  Future<bool> permitidas() async => permiso;
  @override
  Future<bool> pedirPermiso() async {
    pedidosDePermiso++;
    return permiso = true;
  }

  @override
  Future<void> mostrar(AlertaRuta alerta) async => mostradas.add(alerta);
  @override
  Future<void> cancelarTodas() async => cancelaciones++;

  void tocar(AlertaRuta a) => alTocar!(a);
}

class ServicioFalso implements ServicioViaje {
  int inicios = 0;
  int paradas = 0;
  bool permiteArrancar = true;
  bool bateriaLibre = true;
  int pedidosDeBateria = 0;

  @override
  Future<bool> iniciar() async {
    inicios++;
    return permiteArrancar;
  }

  @override
  Future<void> detener() async => paradas++;
  @override
  Future<bool> bateriaSinRestricciones() async => bateriaLibre;
  @override
  Future<void> pedirSinRestriccionesDeBateria() async => pedidosDeBateria++;
}

class _Memoria implements AlmacenCola {
  String? contenido;
  @override
  Future<String?> leer() async => contenido;
  @override
  Future<void> guardar(String c) async => contenido = c;
}

class BanderasEnMemoria implements AlmacenBanderas {
  final Map<String, String> valores = {};
  @override
  Future<String?> leer(String clave) async => valores[clave];
  @override
  Future<void> guardar(String clave, String valor) async =>
      valores[clave] = valor;
}

/// La app armada como en `main.dart`, con servidor, socket, notificaciones y servicio falsos.
class AppPrueba {
  AppPrueba({
    this.demo = true,
    DateTime? venceEn,
    bool conSesion = true,
    this.viajes = const [],
    this.conGestor = true,
    DateTime Function()? ahora,
  }) {
    FlutterSecureStorage.setMockInitialValues({
      if (conSesion)
        'conductor_jwt': jwtQueVence(
            venceEn ?? DateTime.now().add(const Duration(hours: 6))),
      if (conSesion) 'conductor_user': jsonEncode({'nombre': 'Conductor Demo'}),
    });
    const almacenSeguro = FlutterSecureStorage();
    authService = AuthService(
      httpClient: MockClient(_servidor),
      storage: almacenSeguro,
    );
    api = ApiService(authService, httpClient: MockClient(_servidor));
    auth = AuthProvider(authService, demo: demo);
    if (demo) {
      api.alNoAutorizado = () => auth.terminarSesion(MotivoFinSesion.rechazada);
    }
    ws = WsFalso(authService);
    final simulada = PosicionSimulada();
    wsProvider = WsProvider(ws, simulada: simulada);
    viajeProvider = ViajeProvider(api);
    final ubic = UbicacionDemo(simulada);
    seguimiento = SeguimientoController(
      ubicacion: ubic,
      seguimiento: SeguimientoService(
        cola: ColaPosiciones(_Memoria()),
        abrirFlujo: ubic.flujo,
        enviarLote: (id, p) async => ResultadoLote.recibido,
        cadaLote: const Duration(hours: 1),
      ),
      panico: PanicoService(
          enviar: (id, lat, lng) async => ResultadoPanico.confirmado),
    );
    if (demo && conGestor) {
      gestor = GestorAlertaRuta(
        ws: wsProvider,
        notificador: notificador,
        servicio: servicio,
        almacen: banderas,
        ahora: ahora,
      );
      anfitrion = AnfitrionAlertas(
        gestor: gestor!,
        auth: auth,
        navegador: navegador,
      )..iniciar();
    }
    if (demo) {
      control = ControlSesion(
        auth: auth,
        navegador: navegador,
        demo: true,
        puerta: () => PuertaSesion(demo: demo),
        limpiar: () async {
          await seguimiento.detener();
          await gestor?.reiniciar();
          viajeProvider.reiniciar();
        },
      )..iniciar();
    }
  }

  final bool demo;
  final List<Map<String, dynamic>> viajes;
  final bool conGestor;
  final navegador = GlobalKey<NavigatorState>();
  final notificador = NotificadorFalso();
  final servicio = ServicioFalso();
  final BanderasEnMemoria banderas = BanderasEnMemoria();
  late final AuthService authService;
  late final ApiService api;
  late final AuthProvider auth;
  late final WsFalso ws;
  late final WsProvider wsProvider;
  late final ViajeProvider viajeProvider;
  late final SeguimientoController seguimiento;
  GestorAlertaRuta? gestor;
  AnfitrionAlertas? anfitrion;
  ControlSesion? control;

  /// Si es true, el servidor responde 401 a toda llamada autenticada (token revocado).
  bool revocado = false;

  Future<http.Response> _servidor(http.Request r) async {
    final ruta = r.url.path;
    if (ruta.startsWith('/api/auth/')) {
      return respuestaJson({'detail': 'no simulada'}, 404);
    }
    if (revocado) {
      return respuestaJson({'detail': 'Credenciales inválidas'}, 401);
    }
    if (ruta == '/api/conductor/mis-viajes') {
      return respuestaJson({'viajes': viajes});
    }
    if (RegExp(r'^/api/conductor/viajes/\d+$').hasMatch(ruta)) {
      return respuestaJson({
        'detalle': {'id': 1, 'token': 'T1', 'estado': 'EN_CURSO'},
        'viaje_iniciado': true,
      });
    }
    return respuestaJson({}, 200);
  }

  Widget widget() => widgetCon(PuertaSesion(demo: demo));

  Widget widgetCon(Widget home) => MultiProvider(
        providers: [
          Provider<AuthService>.value(value: authService),
          Provider<ApiService>.value(value: api),
          Provider<UbicacionFuente>.value(value: seguimiento.ubicacion),
          Provider<SeguimientoController>.value(value: seguimiento),
          Provider<AlertasDemo>.value(value: AlertasDemo(gestor)),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ViajeProvider>.value(value: viajeProvider),
          ChangeNotifierProvider<WsProvider>.value(value: wsProvider),
        ],
        child: MaterialApp(
          navigatorKey: navegador,
          home: home,
        ),
      );

  /// Arranca el gestor como lo hace la app al iniciar.
  Future<void> iniciar() async => gestor?.iniciar();

  bool _liberada = false;

  void dispose() {
    if (_liberada) return;
    _liberada = true;
    control?.dispose();
    anfitrion?.dispose();
    gestor?.dispose();
    auth.dispose();
  }
}

/// Mensaje `TRAMO_PROHIBIDO` como lo manda el servidor.
Map<String, dynamic> mensajeTramo({
  String mensaje =
      'Entraste a un tramo prohibido. Sal de la vía y comunícate con operaciones. Ruta permitida: Vía Maicao',
  String tramo = 'Tramo norte',
  String alternativa = 'Vía Maicao',
  Object? alertaId,
  int solicitudId = 1,
}) =>
    {
      'tipo': 'TRAMO_PROHIBIDO',
      'solicitud_id': solicitudId,
      'token': 'T1',
      'mensaje': mensaje,
      'tramo': tramo,
      'alternativa': alternativa,
      if (alertaId != null) 'alerta_id': alertaId,
    };
