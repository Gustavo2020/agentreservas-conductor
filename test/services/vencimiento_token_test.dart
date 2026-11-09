import 'package:agentreservas_conductor/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_demo_prueba.dart';

void main() {
  test('lee el vencimiento (exp) del token', () {
    final vence = DateTime.utc(2026, 10, 28, 18);
    expect(AuthService.vencimientoDe(jwtQueVence(vence)), vence.toLocal());
  });

  test(
      'un token ilegible no tiene vencimiento (la validez la decide el servidor)',
      () {
    expect(AuthService.vencimientoDe('tok'), isNull);
    expect(AuthService.vencimientoDe('a.b.c'), isNull);
    expect(AuthService.vencimientoDe(''), isNull);
  });
}
