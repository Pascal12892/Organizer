import HubCore
import SwiftUI

/// Zeitleiste für Tag und Woche: Stundenraster, Termine als Blöcke, rote Linie für „jetzt“.
struct CalendarTimeline: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let events: [CalendarEventInfo]

    static let hourHeight: CGFloat = 48
    static let gutterWidth: CGFloat = 52
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayRow
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        hourLabels
                        ForEach(days, id: \.self) { day in
                            DayColumn(day: day, events: timedEvents(on: day))
                        }
                    }
                    .frame(height: Self.hourHeight * 24)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    let hour = max(calendar.component(.hour, from: .now) - 2, 7)
                    proxy.scrollTo(min(hour, 16), anchor: .top)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                HStack(spacing: 6) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(.secondary)
                    Text(day, format: .dateTime.day())
                        .fontWeight(isToday ? .semibold : .regular)
                        .monospacedDigit()
                        .foregroundStyle(isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(minWidth: 24, minHeight: 24)
                        .background {
                            if isToday { Circle().fill(.red) }
                        }
                }
                .font(.title3)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.calendarState.selectedDay = day
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var allDayRow: some View {
        let allDay = days.map { day in CalendarMath.events(events, on: day, calendar: calendar).filter(\.isAllDay) }
        if allDay.contains(where: { !$0.isEmpty }) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Text("ganztägig")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.gutterWidth - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(allDay[index]) { event in
                            EventChip(event: event, style: .compact)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hour == 0 ? "" : String(format: "%02d:00", hour))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: Self.gutterWidth - 8, height: Self.hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 8)
                    .offset(y: -7)
                    .id(hour)
            }
        }
    }

    private func timedEvents(on day: Date) -> [CalendarEventInfo] {
        CalendarMath.events(events, on: day, calendar: calendar).filter { !$0.isAllDay }
    }
}

/// Eine Tagesspalte mit Stundenlinien und positionierten Terminen.
private struct DayColumn: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let events: [CalendarEventInfo]

    private let calendar = Calendar.current
    private var hourHeight: CGFloat { CalendarTimeline.hourHeight }

    var body: some View {
        GeometryReader { geometry in
            let placements = TimelineLayout.placements(for: events)
            ZStack(alignment: .topLeading) {
                // Stundenlinien
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(hour) * hourHeight)
                }

                ForEach(events) { event in
                    let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                    let frame = frame(for: event, placement: placement, width: geometry.size.width)
                    EventChip(event: event, style: .block)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }

                if calendar.isDateInToday(day) {
                    TimelineView(.everyMinute) { context in
                        NowIndicator()
                            .offset(y: yPosition(for: context.date) - 4)
                    }
                }
            }
            .frame(width: geometry.size.width, height: hourHeight * 24, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                let hour = min(max(Int(location.y / hourHeight), 0), 23)
                model.calendarState.newEventStart = calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: day))
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: hourHeight * 24)
    }

    private func yPosition(for date: Date) -> CGFloat {
        let start = calendar.startOfDay(for: day)
        let seconds = min(max(date.timeIntervalSince(start), 0), 24 * 3600)
        return CGFloat(seconds / 3600) * hourHeight
    }

    private func frame(for event: CalendarEventInfo, placement: TimelinePlacement, width: CGFloat) -> CGRect {
        let top = yPosition(for: event.start)
        let bottom = max(yPosition(for: event.end), top + hourHeight / 4)
        let columnWidth = (width - 4) / CGFloat(placement.columnCount)
        return CGRect(x: 2 + CGFloat(placement.column) * columnWidth, y: top + 1, width: columnWidth - 2, height: bottom - top - 2)
    }
}

/// Rote Linie mit Punkt für die aktuelle Uhrzeit – wie in Apple Kalender.
private struct NowIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .offset(x: -4)
        .accessibilityHidden(true)
    }
}

#Preview("Hell – Woche") {
    CalendarTimeline(
        days: CalendarMath.weekDays(containing: .now, calendar: .current),
        events: PreviewData.calendar.events(in: CalendarMath.interval(for: .week, containing: .now, calendar: .current), hiddenCalendarIDs: [])
    )
    .environment(PreviewData.model())
    .frame(width: 900, height: 600)
}

#Preview("Dunkel – Tag") {
    CalendarTimeline(
        days: [Calendar.current.startOfDay(for: .now)],
        events: PreviewData.calendar.events(in: CalendarMath.interval(for: .day, containing: .now, calendar: .current), hiddenCalendarIDs: [])
    )
    .environment(PreviewData.model())
    .frame(width: 600, height: 600)
    .preferredColorScheme(.dark)
}
