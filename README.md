# Hub

Lokale macOS-App (macOS 26+, SwiftUI) als Zentrale für Obsidian-Vault, Apple Kalender, Aufgaben und Roadmap.
Kein Server, keine Cloud, kein Account.

- `Hub/` – App (MVVM: `App/`, `Services/`, `ViewModels/`, `Views/`)
- `Packages/HubCore/` – Modelle und Parser ohne UI, mit Unit Tests
- `Samples/Beispiel-Vault/` – kleiner Vault zum Ausprobieren
- `Docs/VAULT-FORMAT.md` – welche Dateien Hub wie liest und schreibt

## Bauen und testen

    open Hub.xcodeproj                                    # in Xcode: ⌘R
    cd Packages/HubCore && swift test                     # Parser-Tests

Die App läuft in der Sandbox. Der Zugriff auf den Vault wird als Security-Scoped Bookmark gespeichert.
Bei lokaler Ad-hoc-Signierung kann ein Bookmark nach einem Neubuild ungültig werden. Hub fragt dann nach dem Ordner.
Mit einem Apple-ID-Team unter *Signing & Capabilities* passiert das nicht.
