#!/bin/bash
# Erzeugt Wissensdateien für ein Claude-Projekt (claude.ai › Projekte) aus dem aktuellen Stand.
# Ergebnis: dist/claude-project/ – die Dateien 01–07 als Projektwissen hochladen,
# den Inhalt von 00-Projektanweisungen.md unter „Anweisungen“ einfügen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/claude-project"
cd "$ROOT"

rm -rf "$OUT"
mkdir -p "$OUT"

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unbekannt)"
DATE="$(date +%Y-%m-%d)"

# Hängt alle versionierten Dateien an, die zu den Mustern passen.
# $1 = Zieldatei, $2 = Titel, $3 = Beschreibung, restliche Argumente = git-Pfadmuster
bundle() {
  local target="$OUT/$1" title="$2" description="$3"
  shift 3
  {
    echo "# $title"
    echo
    echo "$description"
    echo
    echo "Stand: $DATE, Commit $COMMIT. Jede Datei beginnt mit ihrem Pfad im Repository."
    echo
  } > "$target"
  git ls-files -- "$@" | while read -r file; do
    local lang=""
    case "$file" in
      *.swift) lang="swift" ;;
      *.sh) lang="bash" ;;
      *.plist|*.entitlements|*.xml) lang="xml" ;;
      *.md) lang="markdown" ;;
      *.json) lang="json" ;;
    esac
    {
      echo "## \`$file\`"
      echo
      echo "\`\`\`\`$lang"
      cat "$file"
      [ -n "$(tail -c1 "$file")" ] && echo
      echo "\`\`\`\`"
      echo
    } >> "$target"
  done
}

cp Docs/CLAUDE-PROJEKT-ANWEISUNGEN.md "$OUT/00-Projektanweisungen.md"

# 01: Überblick aus der vorhandenen Doku
{
  echo "# Organizer – Überblick"
  echo
  echo "Stand: $DATE, Commit $COMMIT."
  echo
  echo "Enthält README, Entwicklerdoku und das Vault-Format. Code steht in den Dateien 02–06,"
  echo "die vollständige Dateiliste in 07-Dateibaum."
  echo
  for doc in README.md Docs/ENTWICKLUNG.md Docs/VAULT-FORMAT.md; do
    echo "---"
    echo
    echo "<!-- Datei: $doc -->"
    echo
    cat "$doc"
    echo
  done
  echo "---"
  echo
  echo "## Letzte Änderungen (git log)"
  echo
  git log --pretty='- %ad %s' --date=short -n 40
} > "$OUT/01-Ueberblick.md"

bundle 02-OrganizerCore.md "OrganizerCore – Logik ohne UI" \
  "Swift-Paket mit Modellen, Parsern (Frontmatter, Aufgaben-Zeilen, deutsche Datumsangaben), Vault-Scan und -Schreiben, Roadmap, Kalenderlogik und Suche." \
  'Packages/OrganizerCore/Package.swift' 'Packages/OrganizerCore/Sources/OrganizerCore/*'

bundle 03-OrganizerCore-Tests.md "OrganizerCore – Tests" \
  "Unit Tests mit Swift Testing (cd Packages/OrganizerCore && swift test)." \
  'Packages/OrganizerCore/Tests/*'

bundle 04-App-Grundlagen.md "App – Zustand, Services, ViewModels" \
  "AppModel (zentraler Zustand), Services für Vault, Aufgaben, Kalender, Roadmap, Erinnerungen, Mitteilungen, ViewModels sowie Info.plist und Entitlements." \
  'Organizer/App/*' 'Organizer/Services/*' 'Organizer/ViewModels/*' 'Organizer/Info.plist' 'Organizer/Organizer.entitlements'

bundle 05-App-Ansichten.md "App – Ansichten (SwiftUI)" \
  "Alle Views: Seitenleiste, Dashboard, Notizen, Kalender, Aufgaben, Roadmap, Suche, Schnellerfassung, Menüleiste, Einstellungen." \
  'Organizer/Views/*'

bundle 06-Widgets-MCP-Skripte.md "Widgets, MCP-Server und Skripte" \
  "WidgetKit-Erweiterung, MCP-Server organizer-mcp für Claude, Installations- und Paketierskripte." \
  'OrganizerWidgets/*' 'Packages/OrganizerCore/Sources/organizer-mcp/*' 'Scripts/*'

# 07: Dateibaum und Hinweis zur Übersetzungsdatei (die selbst zu groß und wenig aussagekräftig ist)
{
  echo "# Dateibaum"
  echo
  echo "Alle versionierten Dateien (Stand $DATE, Commit $COMMIT). Bilder und Projektdatei sind nicht in den Wissensdateien enthalten."
  echo
  echo '```'
  git ls-files
  echo '```'
  echo
  echo "## Übersetzungen"
  echo
  echo "\`Organizer/Localizable.xcstrings\` (String Catalog, Quellsprache de, Übersetzungen en und ar) mit"
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["strings"]), "Einträgen.")' Organizer/Localizable.xcstrings
  echo "Neue Texte bekommen dort je einen Eintrag mit \"en\" und \"ar\" (state \"translated\")."
} > "$OUT/07-Dateibaum.md"

echo "Fertig: $OUT"
for file in "$OUT"/*; do
  printf "  %-32s %6s KB\n" "$(basename "$file")" "$(( $(wc -c < "$file") / 1024 ))"
done
