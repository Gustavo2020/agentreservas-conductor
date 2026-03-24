#!/usr/bin/env bash
# dev-usb.sh — Lanza la app en dispositivo físico por USB con port-forwarding.
# Uso: bash dev-usb.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   AgentReservas Conductor — USB Debug    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Verificar adb ──────────────────────────────────────────────────────────
if ! command -v adb &>/dev/null; then
  echo -e "${RED}✗ adb no encontrado. Instala Android SDK Platform Tools.${NC}"
  exit 1
fi

# ── 2. Esperar dispositivo ────────────────────────────────────────────────────
echo -e "${YELLOW}▶ Esperando dispositivo USB...${NC}"
adb wait-for-usb-device
DEVICE=$(adb devices | grep -v "List" | grep "device$" | awk '{print $1}' | head -1)

if [ -z "$DEVICE" ]; then
  echo -e "${RED}✗ No se detectó ningún dispositivo.${NC}"
  echo -e "${YELLOW}  • Activa 'Depuración USB' en Ajustes → Opciones de desarrollador.${NC}"
  echo -e "${YELLOW}  • Acepta el diálogo de confianza en el celular.${NC}"
  exit 1
fi

echo -e "${GREEN}  ✓ Dispositivo detectado: ${DEVICE}${NC}"

# ── 3. Port forwarding ────────────────────────────────────────────────────────
echo -e "${YELLOW}▶ Configurando port forwarding...${NC}"
adb -s "$DEVICE" reverse tcp:8001 tcp:8001
adb -s "$DEVICE" reverse tcp:3978 tcp:3978
echo -e "${GREEN}  ✓ celular:8001 → localhost:8001${NC}"
echo -e "${GREEN}  ✓ celular:3978 → localhost:3978${NC}"

# ── 4. Verificar que el backend responde ──────────────────────────────────────
echo -e "${YELLOW}▶ Verificando backend en localhost:8001...${NC}"
if curl -s --max-time 3 http://localhost:8001/api/health &>/dev/null || \
   curl -s --max-time 3 http://localhost:8001/docs &>/dev/null; then
  echo -e "${GREEN}  ✓ Backend accesible${NC}"
else
  echo -e "${YELLOW}  ⚠ Backend no respondió — asegúrate de correr start.sh primero${NC}"
fi

# ── 5. Flutter run en el dispositivo ─────────────────────────────────────────
echo -e "${YELLOW}▶ Iniciando Flutter en dispositivo físico...${NC}"
echo ""
cd "$(dirname "$0")"
flutter run \
  -d "$DEVICE" \
  --dart-define=BASE_URL=http://localhost:8001 \
  --dart-define=WS_BASE_URL=ws://localhost:8001
