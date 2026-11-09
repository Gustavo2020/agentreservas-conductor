# Viasofia Demo (APK de demostración)

Compilación con `--dart-define=MODO_DEMO=true` (id `...demo`, etiqueta «Viasofia Demo»).
Compilar y firmar: `bash scripts/compilar_apk_demo.sh` (necesita el keystore demo en
`~/.config/viasofia-demo/keystore.properties` o la variable `VIASOFIA_DEMO_KEYSTORE_PROPS`).

## Cierre de sesión

En la demo, toda salida de sesión (botón «Cerrar sesión», token vencido a las 6 h, 401 del servidor
por simulación detenida, código nuevo o desenlace desde el panel) lleva a la pantalla del
**código de enlace**. El login de correo y contraseña es de la app de operación y no se construye en
la demo. Lo hace `lib/widgets/control_sesion.dart` (reemplaza toda la pila de pantallas).

## Alerta de ruta prohibida

- El servidor manda `TRAMO_PROHIBIDO` por el WebSocket. `GestorAlertaRuta`
  (`lib/services/gestor_alerta_ruta.dart`) lo recibe en cualquier pantalla, lo deduplica, lanza una
  notificación del sistema de importancia máxima (sonido, vibración, visible en pantalla de
  bloqueo) y `AnfitrionAlertas` muestra el diálogo con «Entendido». Tocar la notificación abre ese
  mismo aviso (también con la app cerrada).
- Mientras hay un viaje conectado corre un **servicio en primer plano** (notificación discreta
  «Viaje en curso», tipo `dataSync`, con wakelock y wifi lock) para que Android no congele la app y
  el WebSocket siga vivo con la app minimizada o la pantalla bloqueada. No usa Firebase ni
  servicios externos.
- El WebSocket de la demo reintenta sin límite con espera creciente (3, 6, 12, 24, 30 s), detecta
  un socket mudo (90 s sin respuesta), y se reconecta al instante al volver la red o al volver a
  la app. Si fallan dos intentos seguidos pregunta al servidor si la sesión sigue vigente.
- Idempotencia: por `alerta_id` si el servidor lo manda; si no, por viaje + tramo + mensaje
  dentro de una ventana de 10 minutos.

## Permisos (Android)

| Permiso | Para qué |
|---|---|
| `POST_NOTIFICATIONS` (Android 13+) | Mostrar la alerta. Se pide con una explicación breve al enlazar (hasta 2 veces si se rechaza). |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` (Android 14+) | Servicio en primer plano del viaje. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Pedir (una sola vez, opcional) salir del ahorro agresivo de batería. |
| `WAKE_LOCK`, `VIBRATE` | Mantener la CPU activa durante el viaje y vibrar con la alerta. |

No se usa `fullScreenIntent`: desde Android 14 solo lo conceden por defecto las apps de llamadas y
alarmas; el aviso emergente con sonido ya aparece con la pantalla bloqueada.

## Limitaciones conocidas

- Algunos fabricantes (Xiaomi/MIUI, Huawei, Oppo, Vivo, Samsung con «ahorro adaptable») matan
  servicios aunque estén en primer plano: en esos teléfonos hay que permitir «Sin restricciones» /
  «Inicio automático» para Viasofia Demo en Ajustes > Batería.
- Doze: el servicio en primer plano con wakelock lo atenúa, pero con la pantalla apagada mucho
  tiempo y sin cargador Android puede retrasar la red unos minutos.
- Quitar la app de recientes detiene el servicio (por diseño: sin sesión no hay nada que vigilar).
- Si Android no deja arrancar el servicio desde segundo plano, se reintenta al volver a la app.
- Sin `alerta_id` del servidor, un reenvío pasada la ventana de 10 minutos se vería como alerta nueva.

## Cómo probarlo en un celular

1. Instalar la APK (sobre la anterior: misma firma) y abrirla. Aceptar el permiso de notificaciones.
2. Desde el panel (Patrix) iniciar una simulación; escribir el código de 6 dígitos en la app.
3. Abrir el viaje: debe aparecer la notificación fija «Viaje en curso».
4. Minimizar la app y bloquear la pantalla. Cuando el vehículo simulado entre al tramo prohibido
   debe sonar/vibrar la notificación «Ruta prohibida»; tocarla abre el aviso con «Entendido».
5. Repetir con ahorro de batería activado y con modo avión 20 s (la app debe reconectarse sola).
6. Detener la simulación en el panel o pulsar «Cerrar sesión»: la app vuelve a la pantalla del código.

Pruebas automáticas: `flutter test` (sesión: `test/widgets/sesion_demo_test.dart`; alerta:
`test/widgets/alerta_ruta_demo_test.dart`; socket: `test/services/ws_service_resiliente_test.dart`).
Los textos de cara al usuario de esta función están en `lib/config/textos_demo_alertas.dart`.
