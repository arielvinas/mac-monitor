#!/bin/zsh
# Instala la última versión de MacMonitor en /Applications.
# Uso: curl -fsSL https://raw.githubusercontent.com/arielvinas/mac-monitor/main/install.sh | zsh
set -euo pipefail

URL=https://github.com/arielvinas/mac-monitor/releases/latest/download/MacMonitor.zip
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Descargando MacMonitor…"
curl -fsSL "$URL" -o "$TMP/MacMonitor.zip"
ditto -x -k "$TMP/MacMonitor.zip" "$TMP"

pkill -x MacMonitor 2>/dev/null || true
rm -rf /Applications/MacMonitor.app
mv "$TMP/MacMonitor.app" /Applications/
open /Applications/MacMonitor.app
echo "MacMonitor instalado en /Applications y en ejecución."
