# Organizer

Lokale macOS-App (macOS 26+, SwiftUI) als Zentrale für Obsidian-Vault, Apple Kalender, Aufgaben und Roadmap.
Kein Server, keine Cloud, kein Account.

- `Organizer/` – App (MVVM: `App/`, `Services/`, `ViewModels/`, `Views/`)
- `Packages/OrganizerCore/` – Modelle und Parser ohne UI, mit Unit Tests
- `Samples/Beispiel-Vault/` – kleiner Vault zum Ausprobieren
- `Docs/VAULT-FORMAT.md` – welche Dateien Organizer wie liest und schreibt

## Bauen und testen

    open Organizer.xcodeproj                                    # in Xcode: ⌘R
    cd Packages/OrganizerCore && swift test                     # Parser-Tests

Die App läuft in der Sandbox. Der Zugriff auf den Vault wird als Security-Scoped Bookmark gespeichert.
Bei lokaler Ad-hoc-Signierung kann ein Bookmark nach einem Neubuild ungültig werden. Organizer fragt dann nach dem Ordner.
Mit einem Apple-ID-Team unter *Signing & Capabilities* passiert das nicht.

## Chat mit Claude

Unter „Claude“ in der Seitenleiste (⌘6) erledigt Claude Aufgaben in natürlicher Sprache: Notizen suchen, lesen
und anlegen, Aufgaben anlegen und ändern, Termine ansehen und anlegen.

- **Zugang:** eigener API-Schlüssel von console.anthropic.com, gespeichert im macOS-Schlüsselbund
  (Einstellungen › Claude). Abrechnung nach Verbrauch über Anthropic.
- **Datenschutz:** Nur der Chat geht ins Internet – deine Nachrichten und was Claude dafür aus dem Vault,
  den Aufgaben und dem Kalender liest. Der Verlauf wird nicht gespeichert.
- **Kontrolle:** Jede Änderung erscheint als Karte mit „Ausführen“/„Ablehnen“ (abschaltbar); ⌘Z macht sie rückgängig.
- **Technik:** Messages API direkt über URLSession (`Packages/OrganizerCore/Sources/OrganizerCore/Assistant`),
  Modell `claude-opus-5-5` (wählbar), Streaming, automatisches Prompt-Caching und
  server-seitiger Rückfall auf ein anderes Modell, falls eine Anfrage abgelehnt wird.

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
