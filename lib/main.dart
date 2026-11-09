import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/viaje_provider.dart';
import 'providers/ws_provider.dart';
import 'screens/puerta_sesion.dart';
import 'services/almacen_prefs.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/cola_posiciones.dart';
import 'services/envios_seguimiento.dart';
import 'services/gestor_alerta_ruta.dart';
import 'services/log_service.dart';
import 'services/notificador_alertas.dart';
import 'services/panico_service.dart';
import 'services/seguimiento_controller.dart';
import 'services/seguimiento_service.dart';
import 'services/servicio_viaje.dart';
import 'services/ubicacion_fuente.dart';
import 'services/vigilante_red.dart';
import 'services/ws_service.dart';
import 'widgets/anfitrion_alertas.dart';
import 'widgets/banda_demo.dart';
import 'widgets/control_sesion.dart';
import 'widgets/dialogo_alerta_ruta.dart' show AlertasDemo;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializar logging persistente antes de runApp para que logFilePath
  // esté disponible desde el primer frame y todos los errores queden en disco.
  await AppLogger.init();
  AppLogger.info('App iniciada',
      context: {'logFile': AppLogger.logFilePath ?? 'N/A'});
  // Solo la demostración usa el servicio en primer plano (alerta de ruta con la app minimizada).
  if (AppConfig.modoDemo) ServicioViajePrimerPlano.prepararPuerto();
  runApp(const AgentReservasConductorApp());
}

class AgentReservasConductorApp extends StatefulWidget {
  const AgentReservasConductorApp({super.key});

  @override
  State<AgentReservasConductorApp> createState() =>
      _AgentReservasConductorAppState();
}

class _AgentReservasConductorAppState extends State<AgentReservasConductorApp>
    with WidgetsBindingObserver {
  static const bool _demo = AppConfig.modoDemo;

  final _navegador = GlobalKey<NavigatorState>();
  late final AuthService _authService;
  late final ApiService _apiService;
  late final WsService _wsService;
  late final PosicionSimulada _simulada;
  late final UbicacionFuente _ubicacion;
  late final SeguimientoController _seguimiento;
  late final AuthProvider _authProvider;
  late final ViajeProvider _viajeProvider;
  late final WsProvider _wsProvider;
  GestorAlertaRuta? _gestor;
  AnfitrionAlertas? _anfitrion;
  ControlSesion? _control;
  VigilanteRed? _red;

  @override
  void initState() {
    super.initState();
    // Servicios (singletons)
    _authService = AuthService();
    _apiService = ApiService(_authService);
    _authProvider = AuthProvider(_authService);
    // Demo: un 401 en cualquier llamada (simulación detenida, código nuevo, token revocado)
    // termina la sesión y lleva a la pantalla del código.
    if (_demo) {
      _apiService.alNoAutorizado =
          () => _authProvider.terminarSesion(MotivoFinSesion.rechazada);
    }
    _wsService = WsService(
      _authService,
      resiliente: _demo,
      // Un socket rechazado por sesión revocada se ve igual que una caída de red: se pregunta al
      // servidor con una llamada autenticada (su 401 cierra la sesión).
      verificarSesion: _demo ? _apiService.getMisViajes : null,
    );
    // El seguimiento y el panico viven a nivel de la app, no de una pantalla: el conductor puede
    // salir de la pantalla del viaje (o minimizar la app) y el seguimiento debe continuar.
    // Demo: la posición del vehículo la manda el servidor; no se usa el GPS del teléfono.
    _simulada = PosicionSimulada();
    _ubicacion = _demo ? UbicacionDemo(_simulada) : const UbicacionReal();
    _seguimiento = SeguimientoController(
      ubicacion: _ubicacion,
      seguimiento: SeguimientoService(
        cola: ColaPosiciones(AlmacenPrefs()),
        abrirFlujo: _ubicacion.flujo,
        enviarLote: lotePorHttp(_apiService),
      ),
      panico: PanicoService(enviar: panicoPorHttp(_apiService)),
    );
    _viajeProvider = ViajeProvider(_apiService);
    _wsProvider = WsProvider(_wsService, simulada: _simulada);

    if (_demo) _iniciarDemo();
  }

  /// Todo lo que solo existe en la APK de demostración: alerta de ruta con notificación del
  /// sistema, servicio en primer plano, reconexión del socket y retorno a la pantalla del código.
  void _iniciarDemo() {
    final gestor = GestorAlertaRuta(
      ws: _wsProvider,
      notificador: NotificadorLocal(),
      servicio: ServicioViajePrimerPlano(),
      almacen: const AlmacenBanderasPrefs(),
    );
    _gestor = gestor;
    unawaited(gestor.iniciar());
    _anfitrion = AnfitrionAlertas(
      gestor: gestor,
      auth: _authProvider,
      navegador: _navegador,
    )..iniciar();
    _control = ControlSesion(
      auth: _authProvider,
      navegador: _navegador,
      demo: true,
      puerta: () => const PuertaSesion(),
      limpiar: () async {
        await _seguimiento.detener();
        await gestor.reiniciar();
        _viajeProvider.reiniciar();
      },
    )..iniciar();
    _red = VigilanteRed(alRecuperarRed: _wsProvider.reconectarAhora)..iniciar();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // De vuelta al primer plano: el socket pudo morir y la sesión pudo vencer mientras dormía.
    unawaited(_wsProvider.reconectarAhora());
    _gestor?.sincronizar();
    unawaited(_authProvider.revisarVencimiento());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _red?.dispose();
    _control?.dispose();
    _anfitrion?.dispose();
    _gestor?.dispose();
    _authProvider.dispose();
    _viajeProvider.dispose();
    _wsProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: _authService),
        Provider<ApiService>.value(value: _apiService),
        Provider<WsService>.value(value: _wsService),
        Provider<UbicacionFuente>.value(value: _ubicacion),
        Provider<SeguimientoController>.value(value: _seguimiento),
        Provider<AlertasDemo>.value(value: AlertasDemo(_gestor)),
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
        ChangeNotifierProvider<ViajeProvider>.value(value: _viajeProvider),
        ChangeNotifierProvider<WsProvider>.value(value: _wsProvider),
      ],
      child: MaterialApp(
        navigatorKey: _navegador,
        title: AppConfig.modoDemo ? 'Viasofia Demo' : 'AgentReservas Conductor',
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            BandaDemo(child: child ?? const SizedBox()),
        home: const PuertaSesion(),
      ),
    );
  }
}
