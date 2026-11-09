import Foundation
import HubCore

/// Beispieldaten für SwiftUI-Previews. Greift nie auf echte Dateien zu.
enum PreviewData {
    static func model(withVault: Bool = true) -> AppModel {
        let settings = SettingsStore.inMemory()
        let vault = withVault ? VaultService.preview(snapshot) : VaultService()
        let model = AppModel(settings: settings, vault: vault)
        if withVault {
            model.notes.selectedNoteID = snapshot.notes.first?.id
        }
        return model
    }

    static let snapshot: VaultSnapshot = {
        let layout = VaultLayout()
        let now = Date.now
        let files: [(String, String, TimeInterval)] = [
            ("Uni/Data Science/Vorlesung 4 – Regression.md", markdownSample, 0),
            ("Uni/Data Science/Übungsblatt 3.md", "---\ntags: [uni, übung]\n---\nAufgaben 1–4 bis Freitag.\n\n- [ ] Aufgabe 1\n- [x] Aufgabe 2", -3_600 * 5),
            ("Uni/Statistik/Formelsammlung.md", "# Formelsammlung\nVarianz, Kovarianz und Korrelation. #statistik", -86_400),
            ("Arbeit/Projekt Atlas/Kickoff.md", "---\ntags: [arbeit]\n---\nTeilnehmende, Ziele und nächste Schritte.", -86_400 * 3),
            ("Arbeit/Projekt Atlas/Ideen.md", "Lose Sammlung für [[Kickoff]].", -86_400 * 12),
            ("Freizeit/Reisen/Lissabon.md", "Unterkunft prüfen, Tram 28 fahren. #reisen", -86_400 * 40),
            ("Inbox/Schnelle Notiz.md", "Gedanke für später.", -86_400 * 400),
        ]
        let notes = files.map { path, content, offset in
            NoteFactory.makeNote(
                relativePath: path,
                url: URL(filePath: "/Users/vorschau/Vault/\(path)"),
                content: content,
                modified: now.addingTimeInterval(offset),
                layout: layout
            )
        }
        let topics = [
            Topic(area: "Uni", name: "Data Science", relativePath: "Uni/Data Science"),
            Topic(area: "Uni", name: "Statistik", relativePath: "Uni/Statistik"),
            Topic(area: "Arbeit", name: "Projekt Atlas", relativePath: "Arbeit/Projekt Atlas"),
            Topic(area: "Freizeit", name: "Reisen", relativePath: "Freizeit/Reisen"),
        ]
        let issues = [VaultIssue(relativePath: "Inbox/Kaputt.md", message: "Das Frontmatter wird nicht mit „---“ abgeschlossen.")]
        return VaultSnapshot(notes: notes, topics: topics, issues: issues)
    }()

    static let markdownSample = """
    ---
    bereich: Uni
    thema: Data Science
    erstellt: 2026-11-09T14:30
    tags: [uni, data-science]
    ---
    # Lineare Regression

    Die **Methode der kleinsten Quadrate** minimiert die Summe der *quadrierten* Residuen. Siehe auch [[Formelsammlung]] und `numpy.polyfit`.

    ## Annahmen

    1. Linearität
    2. Unabhängige Fehler
    3. Homoskedastizität

    - [ ] Kapitel 2 lesen 📅 2026-11-20
    - [x] Folien herunterladen

    > Alle Modelle sind falsch, aber manche sind nützlich.

    | Größe | Symbol |
    |---|---|
    | Steigung | β₁ |
    | Achsenabschnitt | β₀ |

    ```python
    import numpy as np
    b1, b0 = np.polyfit(x, y, 1)
    ```
    """
}
