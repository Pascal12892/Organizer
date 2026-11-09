import Foundation
import HubCore

/// Beispieldaten für SwiftUI-Previews. Greift nie auf echte Dateien zu.
enum PreviewData {
    static func model(withVault: Bool = true) -> AppModel {
        let settings = SettingsStore.inMemory()
        let vault = withVault ? VaultService.preview(snapshot) : VaultService()
        let model = AppModel(settings: settings, vault: vault, calendar: calendar)
        if withVault {
            model.notes.selectedNoteID = snapshot.notes.first?.id
        }
        return model
    }

    static var calendar: CalendarService {
        let calendars = [
            CalendarInfo(id: "uni", title: "Uni", color: .blue, sourceTitle: "iCloud", allowsModifications: true),
            CalendarInfo(id: "arbeit", title: "Arbeit", color: .orange, sourceTitle: "iCloud", allowsModifications: true),
            CalendarInfo(id: "feiertage", title: "Feiertage", color: .green, sourceTitle: "Abonnements", allowsModifications: false),
        ]
        let day = Calendar.current.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Double) -> Date {
            Calendar.current.date(byAdding: .day, value: dayOffset, to: day)!.addingTimeInterval(hour * 3600)
        }
        let events = [
            CalendarEventInfo(id: "1", title: "Vorlesung Data Science", start: at(0, 10), end: at(0, 11.5), calendarID: "uni", location: "Hörsaal 3"),
            CalendarEventInfo(id: "2", title: "Team-Meeting", start: at(0, 11), end: at(0, 12), calendarID: "arbeit"),
            CalendarEventInfo(id: "3", title: "Abgabe Übungsblatt", start: at(1, 0), end: at(2, 0), isAllDay: true, calendarID: "uni"),
            CalendarEventInfo(id: "4", title: "Sprint-Review", start: at(2, 14), end: at(2, 15), calendarID: "arbeit"),
            CalendarEventInfo(id: "5", title: "Tutorium", start: at(-1, 16), end: at(-1, 17.5), calendarID: "uni"),
        ]
        return CalendarService(previewCalendars: calendars, events: events)
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
        let folders = ["Uni", "Uni/Data Science", "Uni/Statistik", "Arbeit", "Arbeit/Projekt Atlas", "Freizeit", "Freizeit/Reisen", "Inbox"]
        return VaultSnapshot(notes: notes, topics: topics, issues: issues, folders: folders)
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
