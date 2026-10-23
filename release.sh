#!/bin/zsh
# Publica una versión nueva: sube la versión, compila, firma, notariza y crea el release en GitHub.
# Uso: ./release.sh 1.2 ["notas del release"]
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?Uso: ./release.sh <versión> [notas]}
NOTES=${2:-}
TAG=v$VERSION

[[ -z "$(git status --porcelain)" ]] || { echo "Hay cambios sin commitear: commitealos antes de publicar."; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo "Publicá desde main."; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "El tag $TAG ya existe."; exit 1; }
security find-identity -v -p codesigning | grep -q '"Developer ID Application: ' \
    || { echo "Falta el certificado Developer ID Application en el llavero."; exit 1; }
git pull --ff-only -q

# CFBundleShortVersionString = versión visible; CFBundleVersion = número de build, sube de a uno.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" Info.plist

./build.sh --zip

git commit -q -m "Release $TAG" Info.plist
git tag "$TAG"
git push -q origin main "$TAG"

INSTALL='curl -fsSL https://raw.githubusercontent.com/arielvinas/mac-monitor/main/install.sh | zsh'
gh release create "$TAG" build/MacMonitor.zip --title "MacMonitor $VERSION" \
    --notes "${NOTES:+$NOTES

}Build universal (Apple Silicon + Intel), macOS 13+, firmado con Developer ID y notarizado por Apple.

Instalar:
\`\`\`sh
$INSTALL
\`\`\`"
echo "Publicado $TAG"
