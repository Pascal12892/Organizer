# Organizer

Lokale macOS-App (macOS 26+, SwiftUI) als Zentrale für Obsidian-Vault, Apple Kalender, Aufgaben und Roadmap.
Kein Server, keine Cloud, kein Account.

- `Organizer/` – App (MVVM: `App/`, `Services/`, `ViewModels/`, `Views/`)
- `Packages/OrganizerCore/` – Modelle und Parser ohne UI, mit Unit Tests
- `Samples/Beispiel-Vault/` – kleiner Vault zum Ausprobieren
- `Docs/VAULT-FORMAT.md` – welche Dateien Organizer wie liest und schreibt

## Bauen und testen

    open Organizer.xcodeproj                                    # in Xcode: ⌘R (Debug, zum Entwickeln)
    Scripts/install-app.sh                                      # optimierter Build nach /Applications – für den Alltag
    cd Packages/OrganizerCore && swift test                     # Parser-Tests

Die App läuft in der Sandbox. Der Zugriff auf den Vault wird als Security-Scoped Bookmark gespeichert.
Bei lokaler Ad-hoc-Signierung kann ein Bookmark nach einem Neubuild ungültig werden. Organizer fragt dann nach dem Ordner.
Mit einem Apple-ID-Team unter *Signing & Capabilities* passiert das nicht.

## Schnellerfassung

Systemweit mit **⌃⌥ Leertaste** (änderbar unter Einstellungen › Allgemein) oder im Dashboard.
⇥ wechselt zwischen Aufgabe, Termin und Notiz, ⏎ speichert, esc schließt.

Verstanden werden u. a.: heute, morgen, übermorgen, Freitag, nächsten Montag, nächste Woche, Ende der Woche,
in 3 Tagen, in zwei Wochen, 20.11., 20. November, 2026-11-20, 14 Uhr, um 9, 18:30, abends –
dazu `!`/`!!`/`!!!` als Priorität und `#bereich` zur Zuordnung.

## Drag and Drop

- Aufgaben auf einen Tag im Kalender ziehen → Fälligkeit.
- Notizen auf einen Ordner in der Seitenleiste ziehen → verschieben (Bereich/Thema im Frontmatter werden angepasst).
- Ordner aus dem Finder auf einen Ordner in der Seitenleiste ziehen → als Mac-Ordner verknüpfen.

Alles lässt sich mit ⌘Z rückgängig machen.

## Claude über MCP (mit deinem Claude-Abo)

Organizer bringt einen MCP-Server mit (`Packages/OrganizerCore/Sources/organizer-mcp`). Damit nutzt Claude in der
Desktop-App oder in Claude Code – über dein Abo, ohne API-Schlüssel – deinen Vault, deine Aufgaben und den Kalender:
Notizen suchen, lesen, anlegen und ergänzen, Aufgaben ansehen, anlegen und ändern, Roadmap ansehen, Termine ansehen und anlegen.

1. Einmalig installieren: `Scripts/install-mcp.sh` (legt `~/.local/bin/organizer-mcp` an).
2. Verbinden – die fertigen Befehle mit deinem Vault-Pfad stehen in Organizer unter Einstellungen › Claude:
   - Claude Code: `claude mcp add --scope user organizer -- ~/.local/bin/organizer-mcp --vault "/Pfad/zum/Vault"`
   - Claude Desktop: Eintrag `organizer` unter `mcpServers` in `claude_desktop_config.json`.

Claude fragt vor jedem Werkzeugaufruf. Der Server schreibt wie Organizer nur zeilengenau und überschreibt nie Dateien.
Organizer selbst braucht dafür keinen Internetzugang.

## Menüleiste, Mitteilungen, Widgets

- **Menüleiste:** Symbol mit den Terminen und Aufgaben von heute und einer Schnellerfassung
  (abschaltbar unter Einstellungen › Allgemein).
- **Mitteilungen:** Erinnerung am Fälligkeitstag zur gewählten Uhrzeit, für Aufgaben und Meilensteine.
  In der Mitteilung lässt sich eine Aufgabe direkt abhaken.
- **Widgets:** „Heutige Aufgaben“ und „Nächste Termine“ für den Schreibtisch und die Mitteilungszentrale.
  Die App schreibt dafür einen kleinen Auszug in einen gemeinsamen App-Group-Container.
  **Voraussetzung:** In Xcode unter *Signing & Capabilities* für beide Targets (Organizer, OrganizerWidgets)
  dein Team auswählen. Ohne Team gibt es keine gültige App Group, die Widgets zeigen dann nur einen Hinweis.

## Tastatur

| Kürzel | Aktion |
|---|---|
| ⌘1 … ⌘5 | Dashboard, Notizen, Kalender, Aufgaben, Roadmap |
| ⌘N | Neue Notiz (im Kalender: Termin, in Aufgaben: Aufgabe) |
| ⌥⌘N | Neuer Ordner |
| ⌘F | Suchen |
| ⌘E | Bearbeiten / Vorschau |
| ⌥⌘O | In Obsidian öffnen |
| Leertaste | Quick Look (Notizliste), abhaken (Aufgaben) |
| ⏎ | Notiz bearbeiten, im Kalender Tag öffnen |
| ⌘← ⌘→ ⌘T | Kalender zurück, weiter, heute |
| ⌃⌥ Leertaste | Schnellerfassung aus jeder App |
| ⌘Z / ⇧⌘Z | Rückgängig / Wiederholen |
