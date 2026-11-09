#!/bin/bash
# Baut den MCP-Server von Organizer und installiert ihn nach ~/.local/bin/organizer-mcp.
# Danach kann Claude (Desktop-App oder Claude Code, über dein Abo) Vault, Aufgaben und Kalender nutzen.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.local/bin"

echo "Baue organizer-mcp …"
swift build -c release --product organizer-mcp --package-path "$PROJECT/Packages/OrganizerCore"

mkdir -p "$DEST"
cp "$PROJECT/Packages/OrganizerCore/.build/release/organizer-mcp" "$DEST/organizer-mcp"
echo "Installiert: $DEST/organizer-mcp"
echo
echo "Nächster Schritt – in Organizer unter Einstellungen › Claude stehen die passenden Befehle"
echo "für Claude Code und Claude Desktop, schon mit deinem Vault-Pfad."
