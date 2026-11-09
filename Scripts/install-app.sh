#!/bin/bash
# Baut Organizer optimiert (Release) und installiert die App nach /Applications.
# Der Debug-Build aus Xcode (⌘R) ist ohne Optimierungen und spürbar langsamer.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$PROJECT/build/Release"

echo "Baue Organizer (Release) …"
xcodebuild -project "$PROJECT/Organizer.xcodeproj" -scheme Organizer -configuration Release \
  -derivedDataPath "$BUILD" build -quiet

APP="$BUILD/Build/Products/Release/Organizer.app"
if pgrep -x Organizer >/dev/null; then
  echo "Bitte Organizer zuerst beenden (⌘Q) und das Skript erneut starten."
  exit 1
fi
ditto "$APP" /Applications/Organizer.app
echo "Installiert: /Applications/Organizer.app"
