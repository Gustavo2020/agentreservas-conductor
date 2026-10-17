import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/viaje_provider.dart';
import 'providers/ws_provider.dart';
import 'screens/login_screen.dart';
import 'screens/viajes_screen.dart';
import 'services/almacen_prefs.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/cola_posiciones.dart';
import 'services/envios_seguimiento.dart';
import 'services/flujo_geolocator.dart';
import 'services/log_service.dart';
import 'services/panico_service.dart';
import 'services/seguimiento_controller.dart';
import 'services/seguimiento_service.dart';
import 'services/ws_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializar logging persistente antes de runApp para que logFilePath
  // esté disponible desde el primer frame y todos los errores queden en disco.
  await AppLogger.init();
  AppLogger.info('App iniciada',
      context: {'logFile': AppLogger.logFilePath ?? 'N/A'});
  runApp(const AgentReservasConductorApp());
}

class AgentReservasConductorApp extends StatelessWidget {
  const AgentReservasConductorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Servicios (singletons)
    final authService = AuthService();
    final apiService = ApiService(authService);
    final wsService = WsService(authService);
    // El seguimiento y el panico viven a nivel de la app, no de una pantalla: el conductor puede
    // salir de la pantalla del viaje (o minimizar la app) y el seguimiento debe continuar.
    final seguimiento = SeguimientoController(
      seguimiento: SeguimientoService(
        cola: ColaPosiciones(AlmacenPrefs()),
        abrirFlujo: flujoGeolocator,
        enviarLote: lotePorHttp(apiService),
      ),
      panico: PanicoService(enviar: panicoPorHttp(apiService)),
    );

    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
        Provider<WsService>.value(value: wsService),
        Provider<SeguimientoController>.value(value: seguimiento),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService),
        ),
        ChangeNotifierProvider(
          create: (_) => ViajeProvider(apiService),
        ),
        ChangeNotifierProvider(
          create: (_) => WsProvider(wsService),
        ),
      ],
      child: MaterialApp(
        title: 'AgentReservas Conductor',
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const _SplashGate(),
      ),
    );
  }
}

/// Decide si mostrar Login o lista de viajes según el estado de sesión.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<AuthProvider>().checkAuth();
      } catch (_) {
        // If secure storage fails, treat as unauthenticated
        if (mounted) context.read<AuthProvider>().forceUnauthenticated();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return switch (auth.state) {
      AuthState.unknown => const Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
      AuthState.authenticated => const ViajesScreen(),
      AuthState.unauthenticated => const LoginScreen(),
    };
  }
}
