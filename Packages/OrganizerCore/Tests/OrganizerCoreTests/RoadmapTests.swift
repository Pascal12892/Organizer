import Foundation
import Testing
@testable import OrganizerCore

@Suite("Roadmap")
struct RoadmapTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    let content = """
    ---
    bereich: Uni
    start: 2026-11-01
    ende: 2027-03-31
    status: in Arbeit
    farbe: blue
    ---
    # Bachelorarbeit

    Ziel: fertig werden.

    ## Literaturrecherche
    start:: 2026-11-01
    ende:: 2026-11-30
    status:: in Arbeit

    - [x] Quellen sammeln
    - [ ] Exposé schreiben 📅 2026-11-20
    - [-] Verworfen

    ## Schreiben
    start:: 2026-12-01
    ende:: 2027-02-28

    ## Abgabe
    status:: erledigt
    """

    func makeProject() -> RoadmapProject {
        let note = NoteFactory.makeNote(relativePath: "_Organizer/Roadmap/Bachelorarbeit.md", url: URL(filePath: "/v/x"),
                                        content: content, modified: .now, layout: VaultLayout())
        return RoadmapParser.project(from: note, tasks: TaskExtractor.tasks(in: note), timeZone: berlin)
    }

    @Test func parsesProjectAndMilestones() {
        let project = makeProject()
        #expect(project.title == "Bachelorarbeit")
        #expect(project.status == .active)
        #expect(project.color == "blue")
        #expect(project.start == day(2026, 11, 1) && project.end == day(2027, 3, 31))
        #expect(project.milestones.map(\.title) == ["Literaturrecherche", "Schreiben", "Abgabe"])
        let first = project.milestones[0]
        #expect(first.start == day(2026, 11, 1) && first.end == day(2026, 11, 30))
        #expect(first.status == .active)
        #expect(first.tasks.map(\.title) == ["Quellen sammeln", "Exposé schreiben", "Verworfen"])
        #expect(first.progress == 0.5) // abgebrochene zählen nicht
        #expect(first.headingLine == 11)
        #expect(project.milestones[1].status == .planned && project.milestones[1].progress == 0)
        #expect(project.milestones[2].progress == 1)
    }

    @Test func statusIsTolerant() {
        #expect(MilestoneStatus(text: "Done") == .done)
        #expect(MilestoneStatus(text: "aktiv") == .active)
        #expect(MilestoneStatus(text: nil) == .planned)
        #expect(RoadmapParser.field(in: "- [ ] Aufgabe:: mit Doppelpunkten") == nil)
    }

    @Test func settingFieldsChangesOnlyThoseLines() {
        let raw = "# P\n\n## M\nstart:: 2026-11-01\nstatus:: geplant\n\n- [ ] A\n"
        let result = RoadmapEditor.setting([("status", "erledigt"), ("ende", "2026-11-30")], milestoneAt: 2, in: raw)
        #expect(result == "# P\n\n## M\nstart:: 2026-11-01\nstatus:: erledigt\nende:: 2026-11-30\n\n- [ ] A\n")
        #expect(RoadmapEditor.setting([("start", nil)], milestoneAt: 2, in: raw) == "# P\n\n## M\nstatus:: geplant\n\n- [ ] A\n")
        #expect(RoadmapEditor.setting([("status", "x")], milestoneAt: 99, in: raw) == raw)
    }

    @Test func insertsTasksAtEndOfMilestone() {
        let raw = "## M\nstatus:: geplant\n\n- [ ] A\n\n## N\nstatus:: geplant\n"
        #expect(RoadmapEditor.insertingTask("- [ ] B", milestoneAt: 0, in: raw) == "## M\nstatus:: geplant\n\n- [ ] A\n- [ ] B\n\n## N\nstatus:: geplant\n")
        #expect(RoadmapEditor.insertingTask("- [ ] C", milestoneAt: 5, in: raw) == "## M\nstatus:: geplant\n\n- [ ] A\n\n## N\nstatus:: geplant\n\n- [ ] C\n")
    }

    @Test func appendsMilestoneAndBuildsProject() {
        let raw = "# P\nText"
        let result = RoadmapEditor.appendingMilestone(title: "Neu", start: day(2026, 12, 1), end: nil, to: raw, timeZone: berlin)
        #expect(result == "# P\nText\n\n## Neu\nstart:: 2026-12-01\nstatus:: geplant\n")

        let file = RoadmapEditor.newProject(title: "Umzug", area: "Freizeit", start: day(2026, 12, 1), end: day(2027, 1, 15), color: "green", timeZone: berlin)
        let note = NoteFactory.makeNote(relativePath: "_Organizer/Roadmap/Umzug.md", url: URL(filePath: "/x"), content: file, modified: .now, layout: VaultLayout())
        let project = RoadmapParser.project(from: note, tasks: [], timeZone: berlin)
        #expect(project.area == "Freizeit" && project.color == "green" && project.end == day(2027, 1, 15))
        #expect(project.milestones.isEmpty)
    }
}
