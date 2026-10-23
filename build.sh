#!/bin/zsh
# Compila MacMonitor.app (universal: Apple Silicon + Intel). Uso: ./build.sh [--install | --zip]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MacMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        Sources/*.swift -o "build/MacMonitor-$arch"
done
lipo -create build/MacMonitor-arm64 build/MacMonitor-x86_64 -output "$APP/Contents/MacOS/MacMonitor"
rm build/MacMonitor-arm64 build/MacMonitor-x86_64
codesign --force --sign - "$APP"
echo "Compilado: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MacMonitor 2>/dev/null || true
    rm -rf /Applications/MacMonitor.app
    cp -R "$APP" /Applications/
    open /Applications/MacMonitor.app
    echo "Instalado en /Applications y en ejecución"
fi

# Zip para subir a un release de GitHub (lo descarga install.sh).
if [[ "${1:-}" == "--zip" ]]; then
    rm -f build/MacMonitor.zip
    ditto -c -k --keepParent "$APP" build/MacMonitor.zip
    echo "Empaquetado: build/MacMonitor.zip"
fi
