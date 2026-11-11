import OrganizerCore
import SwiftUI

/// Zeile in der Notizliste: Titel, Datum und Vorschau – angelehnt an Apple Notizen.
struct NoteRow: View {
    let note: Note
    var showsLocation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(note.modified, format: Self.dateStyle(for: note.modified))
                    .foregroundStyle(.primary)
                Text(note.excerpt.isEmpty ? L("Kein weiterer Text") : note.excerpt)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)

            if showsLocation, let location {
                Label(location, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var location: String? {
        note.folderPath.isEmpty ? nil : note.folderPath.replacingOccurrences(of: "/", with: " › ")
    }

    /// Heute nur die Uhrzeit, sonst das Datum – wie in Notizen und Mail.
    static func dateStyle(for date: Date) -> Date.FormatStyle {
        Calendar.current.isDateInToday(date)
            ? .dateTime.hour().minute()
            : .dateTime.day().month(.twoDigits).year(.twoDigits)
    }
}

#Preview("Hell") {
    List(PreviewData.snapshot.notes.prefix(3)) { note in
        NoteRow(note: note)
    }
    .frame(width: 320, height: 260)
}

#Preview("Dunkel") {
    List(PreviewData.snapshot.notes.prefix(3)) { note in
        NoteRow(note: note)
    }
    .frame(width: 320, height: 260)
    .preferredColorScheme(.dark)
}
