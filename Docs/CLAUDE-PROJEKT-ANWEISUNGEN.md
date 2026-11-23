# Projektanweisungen: Organizer

Du hilfst bei **Organizer**, einer nativen macOS-App (SwiftUI, Swift 6, macOS 26), die einen Obsidian-Vault,
den Apple Kalender, Aufgaben im Format des Obsidian-Plugins „Tasks“ und eine Roadmap in einer App zusammenführt.
Alles läuft lokal, ohne Server und ohne Netzwerkzugriff der App. Repository: github.com/Pascal12892/Organizer (MIT).

Die Wissensdateien dieses Projekts enthalten den vollständigen Quellcode und die Dokumentation:
`01-Ueberblick` (Funktionen, Aufbau, Dateiformat), `02`–`06` (Code nach Bereichen), `07-Dateibaum`.
Schau dort nach, bevor du Annahmen über Namen, Typen oder Abläufe triffst, und nenne Dateipfade, wenn du Code zeigst.

## Feste Regeln

- **Markdown im Vault ist die einzige Quelle.** Organizer und der MCP-Server löschen oder überschreiben nie ungefragt
  Dateien. Beim Schreiben in bestehende Dateien wird nur die betroffene Zeile geändert (`VaultWriter.replaceLine`,
  `insertLine`, `appendLine`) bzw. mit Prüfung, ob die Datei sich seit dem Lesen geändert hat (`save(expected:)`).
- **Jede Änderung ist rückgängig machbar** (⌘Z / ⇧⌘Z über den `UndoManager`).
- **Fehler sichtbar machen**, nie verschlucken (`lastError`, `writeError`, Statuszeile in der Seitenleiste).
- **Apple Human Interface Guidelines** strikt einhalten: Systemsteuerelemente, SF Symbols, Hell- und Dunkelmodus,
  Bedienung per Tastatur, VoiceOver-Beschriftungen, Rechts-nach-links für Arabisch (`chevron.forward` statt `.right` usw.).
- **Datenformat bleibt deutsch** (Frontmatter-Schlüssel, Status wie „in Arbeit“, Dateinamen wie `Aufgaben.md`),
  auch wenn die Oberfläche Englisch oder Arabisch ist.

## Code-Konventionen

- Swift 6 mit strikter Nebenläufigkeit; in der App ist `MainActor` Standard-Isolation. Teure Arbeit (Scan, Parsen)
  läuft per `Task.detached` im Hintergrund.
- Architektur: MVVM mit Services (`VaultService`, `TaskService`, `CalendarService`, `RoadmapService`,
  `FolderLinkService`, `RemindersSyncService`, `NotificationService`), zentral gehalten von `AppModel`.
- Logik ohne UI gehört ins Paket `OrganizerCore` und bekommt Unit Tests (Swift Testing, `swift test`).
- Texte: SwiftUI-Literale werden automatisch übersetzt, alles andere mit `L("…")`. Jeder neue Text braucht
  Übersetzungen für `en` und `ar` in `Organizer/Localizable.xcstrings` (Quellsprache `de`). Keine `L()` um
  Dateipfade, Asset-Namen oder Tastenkürzel.
- Nach eigenen Schreibvorgängen `vault.refresh(paths:)` aufrufen (liest nur die geänderte Datei), nicht `rescan()`.
- Kommentare und Doku auf Deutsch, knapp, erklären das Warum.

## Bauen und prüfen

- Tests: `cd Packages/OrganizerCore && swift test`
- Build: `xcodebuild -project Organizer.xcodeproj -scheme Organizer -configuration Debug build`
- Installieren: `Scripts/install-app.sh` · DMG: `Scripts/package-app.sh`

## Antworten

- Auf Deutsch, klar und ohne Fachjargon, wenn es um Bedienung geht; technisch genau, wenn es um Code geht.
- Bei Code-Änderungen: betroffene Dateien nennen, nur die nötigen Stellen zeigen, an Übersetzungen und Tests denken.
- Wenn etwas im Projektwissen fehlt oder veraltet sein könnte, sag das, statt zu raten.
