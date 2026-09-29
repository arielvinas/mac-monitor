#!/bin/zsh
# Compila MacMonitor.app. Uso: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MacMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    Sources/*.swift -o "$APP/Contents/MacOS/MacMonitor"
codesign --force --sign - "$APP"
echo "Compilado: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MacMonitor 2>/dev/null || true
    rm -rf /Applications/MacMonitor.app
    cp -R "$APP" /Applications/
    open /Applications/MacMonitor.app
    echo "Instalado en /Applications y en ejecución"
fi
