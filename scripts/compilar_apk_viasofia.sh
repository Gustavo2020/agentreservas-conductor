#!/usr/bin/env bash
# Compila la APK REAL de Viasofia (sin MODO_DEMO) firmada con la llave de lanzamiento y la deja en apk/.
#   apk/viasofia-vX.Y.Z-YYYYMMDD.apk  y  apk/viasofia.apk (copia final)  +  apk/viasofia.apk.sha256
# Para distribuirla se copia (viasofia.apk y su .sha256) a la carpeta de descargas del host, de donde la
# baja la pastilla del front de Viasofia (https://gsx-2.com/descargas/viasofia.apk).
# Requisitos: JDK 17 (Gradle pide 17-24; el JDK por defecto del host puede ser otro).
#   JAVA_HOME_VIASOFIA  JDK 17 a usar solo en esta compilacion (def. ~/.local/jdks/jdk-17*)
#   VIASOFIA_RELEASE_KEYSTORE_PROPS  .properties de la llave de lanzamiento, FUERA del repo
#                    (def. ~/.config/viasofia-release/keystore.properties; obligatorio: sin el el script falla)
#   BASE_URL / WS_BASE_URL  (def. https://viasofia.gsx-2.com / wss://viasofia.gsx-2.com)
# La llave de lanzamiento debe respaldarse: sin ella no se puede actualizar una app ya instalada.
set -euo pipefail
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME_VIASOFIA:-$(ls -d "$HOME"/.local/jdks/jdk-17* 2>/dev/null | head -1)}"
[ -x "$JDK/bin/java" ] || { echo "Falta un JDK 17 (JAVA_HOME_VIASOFIA)"; exit 1; }
export JAVA_HOME="$JDK" PATH="$JDK/bin:$PATH"

PROPS="${VIASOFIA_RELEASE_KEYSTORE_PROPS:-$HOME/.config/viasofia-release/keystore.properties}"
[ -f "$PROPS" ] || { echo "ERROR: falta la llave de lanzamiento ($PROPS). No se firma con la llave debug."; exit 1; }
export VIASOFIA_RELEASE_KEYSTORE_PROPS="$PROPS"

# /mnt/t7 esta montado noexec: Flutter no puede ejecutar android/gradlew desde ahi. Se compila en una
# copia bajo ~/.cache (sin .git, build ni apk) y solo se trae la APK de vuelta.
ORIGEN="$PWD"
TRABAJO="${TRABAJO_VIASOFIA:-$HOME/.cache/viasofia-build}"
mkdir -p "$TRABAJO"
rsync -a --delete --exclude .git --exclude build --exclude apk --exclude .dart_tool \
  --exclude android/.gradle "$ORIGEN"/ "$TRABAJO"/
cd "$TRABAJO"
chmod +x android/gradlew

VERSION="$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' pubspec.yaml)"
FECHA="$(date +%Y%m%d)"
flutter build apk --release \
  --dart-define=BASE_URL="${BASE_URL:-https://viasofia.gsx-2.com}" \
  --dart-define=WS_BASE_URL="${WS_BASE_URL:-wss://viasofia.gsx-2.com}"

SALIDA="$ORIGEN/apk"
mkdir -p "$SALIDA"
cp build/app/outputs/flutter-apk/app-release.apk "$SALIDA/viasofia-v${VERSION}-${FECHA}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$SALIDA/viasofia.apk"
(cd "$SALIDA" && sha256sum viasofia.apk | tee viasofia.apk.sha256)
ls -l "$SALIDA"/viasofia*.apk
