#!/usr/bin/env bash
# Compila la APK de demostración de Viasofia (MODO_DEMO) y la deja en apk/.
#   apk/viasofia-demo-vX.Y.Z-YYYYMMDD.apk  y  apk/viasofia-demo.apk (copia final)
# Requisitos: JDK 17 (Gradle pide 17-24; el JDK por defecto del host puede ser otro).
#   JAVA_HOME_DEMO   JDK 17 a usar solo en esta compilación (def. ~/.local/jdks/jdk-17*)
#   VIASOFIA_DEMO_KEYSTORE_PROPS  .properties de la llave de la demo, FUERA del repo
#                    (def. ~/.config/viasofia-demo/keystore.properties; obligatorio: sin él el script falla)
#   BASE_URL / WS_BASE_URL  (def. https://viasofia.gsx-2.com / wss://viasofia.gsx-2.com)
set -euo pipefail
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME_DEMO:-$(ls -d "$HOME"/.local/jdks/jdk-17* 2>/dev/null | head -1)}"
[ -x "$JDK/bin/java" ] || { echo "Falta un JDK 17 (JAVA_HOME_DEMO)"; exit 1; }
export JAVA_HOME="$JDK" PATH="$JDK/bin:$PATH"

PROPS="${VIASOFIA_DEMO_KEYSTORE_PROPS:-$HOME/.config/viasofia-demo/keystore.properties}"
[ -f "$PROPS" ] || { echo "ERROR: falta el keystore de demo ($PROPS). No se firma con la llave debug."; exit 1; }
export VIASOFIA_DEMO_KEYSTORE_PROPS="$PROPS"

# /mnt/t7 está montado noexec: Flutter no puede ejecutar android/gradlew desde ahí. Se compila en una
# copia bajo ~/.cache (sin .git, build ni apk) y solo se trae la APK de vuelta.
ORIGEN="$PWD"
TRABAJO="${TRABAJO_DEMO:-$HOME/.cache/viasofia-demo-build}"
mkdir -p "$TRABAJO"
rsync -a --delete --exclude .git --exclude build --exclude apk --exclude .dart_tool \
  --exclude android/.gradle "$ORIGEN"/ "$TRABAJO"/
cd "$TRABAJO"
chmod +x android/gradlew

VERSION="$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' pubspec.yaml)"
FECHA="$(date +%Y%m%d)"
flutter build apk --release \
  --dart-define=MODO_DEMO=true \
  --dart-define=BASE_URL="${BASE_URL:-https://viasofia.gsx-2.com}" \
  --dart-define=WS_BASE_URL="${WS_BASE_URL:-wss://viasofia.gsx-2.com}"

SALIDA="$ORIGEN/apk"
mkdir -p "$SALIDA"
cp build/app/outputs/flutter-apk/app-release.apk "$SALIDA/viasofia-demo-v${VERSION}-${FECHA}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$SALIDA/viasofia-demo.apk"
(cd "$SALIDA" && sha256sum viasofia-demo.apk | tee viasofia-demo.apk.sha256)
ls -l "$SALIDA"/viasofia-demo*.apk
