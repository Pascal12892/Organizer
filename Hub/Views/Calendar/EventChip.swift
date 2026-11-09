import HubCore
import SwiftUI

/// Darstellung eines Termins: kompakt (Monat, ganztägig) oder als Block (Zeitleiste).
/// Ein Klick zeigt die Details in einem Popover.
struct EventChip: View {
    enum Style { case compact, block }

    @Environment(AppModel.self) private var model
    let event: CalendarEventInfo
    let style: Style
    @State private var showsDetails = false

    var body: some View {
        let color = model.calendar.color(for: event.calendarID)

        Button {
            showsDetails = true
        } label: {
            switch style {
            case .compact: compact(color: color)
            case .block: block(color: color)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            EventDetailView(event: event) {
                showsDetails = false
                model.createNote(for: event)
            }
        }
        .help(event.title)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func compact(color: Color) -> some View {
        if event.isAllDay {
            Text(event.title)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(event.title)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(event.start, format: .dateTime.hour().minute())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
    }

    private func block(color: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let location = event.location {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var accessibilityText: String {
        if event.isAllDay { return "\(event.title), ganztägig" }
        return "\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)) bis \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Details eines Termins im Popover.
struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEventInfo
    let createNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text(timeText)
                    .foregroundStyle(.secondary)
            }

            if let calendar = model.calendar.calendar(withID: event.calendarID) {
                Label {
                    Text(calendar.title)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(calendar.color)
                }
            }
            if let location = event.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .textSelection(.enabled)
            }
            if let notes = event.notes {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }

            Divider()

            Button("Notiz zum Termin anlegen …", systemImage: "note.text.badge.plus", action: createNote)
                .disabled(model.vault.state != .ready)
                .help("Legt eine Notiz an, die im Frontmatter auf diesen Termin verweist")
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }

    private var timeText: String {
        if event.isAllDay {
            let last = Calendar.current.date(byAdding: .second, value: -1, to: event.end) ?? event.end
            if Calendar.current.isDate(event.start, inSameDayAs: last) {
                return event.start.formatted(date: .complete, time: .omitted) + ", ganztägig"
            }
            return (event.start..<last).formatted(.interval.day().month(.wide).year())
        }
        return (event.start..<event.end).formatted(.interval.weekday(.wide).day().month(.wide).hour().minute())
    }
}
