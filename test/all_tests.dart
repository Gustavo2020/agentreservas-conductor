// Punto de entrada para ejecutar toda la suite de tests.
//
// Ejecutar: flutter test test/all_tests.dart
//
// O por categoría:
//   flutter test test/models/
//   flutter test test/services/
//   flutter test test/providers/
//   flutter test test/widgets/

// Modelos
import 'models/checklist_test.dart' as checklist_test;
import 'models/soporte_test.dart' as soporte_test;
import 'models/trayecto_test.dart' as trayecto_test;
import 'models/viaje_test.dart' as viaje_test;
import 'providers/auth_provider_test.dart' as auth_provider_test;
import 'providers/viaje_provider_test.dart' as viaje_provider_test;
import 'providers/ws_provider_test.dart' as ws_provider_test;
import 'services/api_service_test.dart' as api_service_test;
import 'services/auth_service_test.dart' as auth_service_test;
import 'services/cola_posiciones_test.dart' as cola_posiciones_test;
import 'services/envios_seguimiento_test.dart' as envios_seguimiento_test;
import 'services/panico_service_test.dart' as panico_service_test;
import 'services/seguimiento_controller_test.dart'
    as seguimiento_controller_test;
import 'services/seguimiento_service_test.dart' as seguimiento_service_test;
import 'services/ws_service_test.dart' as ws_service_test;
import 'widgets/boton_panico_test.dart' as boton_panico_test;
import 'widgets/estado_badge_test.dart' as estado_badge_test;
import 'widgets/loading_overlay_test.dart' as loading_overlay_test;

void main() {
  viaje_test.main();
  checklist_test.main();
  soporte_test.main();
  trayecto_test.main();

  auth_service_test.main();
  api_service_test.main();
  ws_service_test.main();
  cola_posiciones_test.main();
  seguimiento_service_test.main();
  seguimiento_controller_test.main();
  panico_service_test.main();
  envios_seguimiento_test.main();

  auth_provider_test.main();
  viaje_provider_test.main();
  ws_provider_test.main();

  boton_panico_test.main();
  estado_badge_test.main();
  loading_overlay_test.main();
}
