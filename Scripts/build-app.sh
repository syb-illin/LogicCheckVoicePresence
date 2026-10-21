#!/bin/bash
# Compile le paquet et assemble un bundle .app lançable.
#
# SwiftPM produit un exécutable nu ; une app macOS a besoin d'un bundle avec son
# Info.plist. Ce script fait le pont, sans Xcode ni projet .xcodeproj à maintenir.
#
# Variables d'environnement :
#   VERSION  version marketing (défaut : dérivée du tag git, sinon 0.0.0)
#   BUILD    numéro de build   (défaut : nombre de commits)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="LogicCheckVoicePresence"
DISPLAY_NAME="Logic Check Voice Presence"
BUNDLE_ID="io.github.sybillin.LogicCheckVoicePresence"
MIN_MACOS="14.0"

# Majeur et mineur viennent du fichier VERSION, le patch du nombre de commits :
# même règle qu'en CI, pour qu'un build local porte la version qu'il aurait eue
# une fois publié.
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
if [ -z "${VERSION:-}" ]; then
    BASE=$(tr -d '[:space:]' < ./VERSION 2>/dev/null || echo 0.0)
    VERSION="${BASE}.${BUILD}"
fi

echo "▸ Compilation de $APP_NAME $VERSION (build $BUILD)"
swift build -c release --product "$APP_NAME"

BIN_PATH="$(swift build -c release --show-bin-path)"
APP_BUNDLE="build/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© $(date +%Y) Ren</string>
</dict>
</plist>
PLIST

# Signature ad hoc : suffisante pour lancer l'app localement. Une vraie
# signature Developer ID demanderait un certificat payant ; sans elle Gatekeeper
# exige un clic droit > Ouvrir au premier lancement, ce que le README explique.
codesign --force --sign - --timestamp=none "$APP_BUNDLE" 2>/dev/null \
    || echo "⚠︎ Signature ad hoc impossible — l'app reste lançable après « clic droit > Ouvrir »"

echo "▸ Bundle : $(pwd)/$APP_BUNDLE"
echo "▸ Lancer : open \"$APP_BUNDLE\""
