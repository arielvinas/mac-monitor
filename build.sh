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
# Con un certificado "Developer ID Application" en el llavero se firma para distribuir (hardened runtime);
# si no hay, firma ad hoc (sólo sirve en esta Mac).
# Se usa el hash del certificado: el nombre puede traer acentos (ñ) que se rompen al pasarlo a codesign.
SIGN_ID=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: / {print $2; exit}')
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    echo "Firmado con Developer ID ($SIGN_ID)"
else
    codesign --force --sign - "$APP"
fi
echo "Compilado: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MacMonitor 2>/dev/null || true
    rm -rf /Applications/MacMonitor.app
    cp -R "$APP" /Applications/
    open /Applications/MacMonitor.app
    echo "Instalado en /Applications y en ejecución"
fi

# Zip para subir a un release de GitHub (lo descarga install.sh).
# Si está firmado con Developer ID, se notariza con el perfil guardado por
# `xcrun notarytool store-credentials macmonitor-notary` y se engrapa el ticket a la app.
if [[ "${1:-}" == "--zip" ]]; then
    rm -f build/MacMonitor.zip
    ditto -c -k --keepParent "$APP" build/MacMonitor.zip
    if [[ -n "$SIGN_ID" ]]; then
        xcrun notarytool submit build/MacMonitor.zip --keychain-profile "${NOTARY_PROFILE:-macmonitor-notary}" --wait
        xcrun stapler staple "$APP"
        rm build/MacMonitor.zip
        ditto -c -k --keepParent "$APP" build/MacMonitor.zip
        echo "Notarizado"
    fi
    echo "Empaquetado: build/MacMonitor.zip"
fi
