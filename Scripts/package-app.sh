#!/bin/bash
# Baut Organizer optimiert und verpackt ihn als DMG zum Weitergeben:
#   dist/Organizer-<Version>.dmg  (App, Verknüpfung zu „Programme“, Kurzanleitung)
# Der MCP-Server für Claude steckt in der App (Contents/Helpers/organizer-mcp).
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$PROJECT/build/Package"
DIST="$PROJECT/dist"
STAGE="$BUILD/dmg"

echo "1/4 Baue Organizer (Release, Apple Silicon und Intel) …"
xcodebuild -project "$PROJECT/Organizer.xcodeproj" -scheme Organizer -configuration Release \
  -derivedDataPath "$BUILD/DerivedData" -destination "generic/platform=macOS" build -quiet 2>&1 \
  | grep -E "error:|BUILD FAILED" || true
APP="$BUILD/DerivedData/Build/Products/Release/Organizer.app"
[ -d "$APP" ] || { echo "Build fehlgeschlagen."; exit 1; }

echo "2/4 Baue den MCP-Server für Claude …"
MCP_ARGS=(-c release --product organizer-mcp --arch arm64 --arch x86_64 --package-path "$PROJECT/Packages/OrganizerCore")
swift build "${MCP_ARGS[@]}" >/dev/null
MCP="$(swift build "${MCP_ARGS[@]}" --show-bin-path)/organizer-mcp"
mkdir -p "$APP/Contents/Helpers"
cp "$MCP" "$APP/Contents/Helpers/organizer-mcp"

cp "$PROJECT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$PROJECT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"

echo "3/4 Signiere neu (ohne Entwicklerkonto: lokal signiert) …"
ENTITLEMENTS="$BUILD/Organizer.entitlements.plist"
codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null
codesign --force --sign - --options runtime "$APP/Contents/Helpers/organizer-mcp"
codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

echo "4/4 Erzeuge DMG …"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -rf "$STAGE" && mkdir -p "$STAGE" "$DIST"
ditto "$APP" "$STAGE/Organizer.app"
ln -s /Applications "$STAGE/Programme"
cp "$PROJECT/Scripts/Erste Schritte.txt" "$STAGE/Erste Schritte – Getting Started.txt"
cp "$PROJECT/LICENSE" "$STAGE/Lizenz – License.txt"
cp "$PROJECT/THIRD-PARTY-NOTICES.md" "$STAGE/Drittanbieter – Third-Party Notices.md"
DMG="$DIST/Organizer-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Organizer $VERSION" -srcfolder "$STAGE" -ov -format ULMO "$DMG" >/dev/null
echo "Fertig: $DMG ($(du -h "$DMG" | cut -f1))"
