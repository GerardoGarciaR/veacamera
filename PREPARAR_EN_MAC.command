#!/bin/bash
set -e

cd "$(dirname "$0")"

echo ""
echo "========================================="
echo "        VEA Camera · Preparación Mac"
echo "========================================="
echo ""

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Este script debe ejecutarse en macOS."
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "No encontré Node.js. Instala Node 22.13+ y vuelve a ejecutar."
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "No encontré las herramientas de Xcode. Abre Xcode y termina su instalación."
  exit 1
fi

echo "Node: $(node -v)"
echo "Instalando dependencias…"
npm install

echo "Alineando paquetes con Expo SDK…"
npx expo install --fix

echo "Generando proyecto iOS y CocoaPods…"
npx expo prebuild --platform ios --clean

echo ""
echo "✅ Proyecto iOS preparado."
echo ""
echo "Ahora conecta tu iPhone y ejecuta:"
echo "  npx expo run:ios --device"
echo ""
echo "Si Xcode pide firma, selecciona tu Personal Team en Signing & Capabilities."
echo ""
