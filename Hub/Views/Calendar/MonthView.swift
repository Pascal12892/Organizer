import HubCore
import SwiftUI

/// Monatsraster wie in Apple Kalender: ganze Wochen, Termine als kompakte Zeilen.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let month: Date
    let events: [CalendarEventInfo]

    private let calendar = Calendar.current
    private static let maxVisibleEvents = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 6)

            Divider()

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<(days.count / 7), id: \.self) { week in
                    GridRow {
                        ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                            DayCell(
                                day: day,
                                isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                events: CalendarMath.events(events, on: day, calendar: calendar),
                                maxVisible: Self.maxVisibleEvents
                            )
                        }
                    }
                }
            }
        }
    }

    /// Kurze Wochentagsnamen, beginnend mit dem ersten Wochentag (Mo).
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isInMonth: Bool
    let events: [CalendarEventInfo]
    let maxVisible: Int

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: model.calendarState.selectedDay)

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Text(day, format: .dateTime.day())
                    .font(.callout.weight(isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? AnyShapeStyle(.white) : (isInMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
                    .frame(minWidth: 22, minHeight: 22)
                    .background {
                        if isToday { Circle().fill(.red) }
                    }
            }

            ForEach(events.prefix(maxVisible)) { event in
                EventChip(event: event, style: .compact)
            }
            if events.count > maxVisible {
                Text("\(events.count - maxVisible) weitere")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .top)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear))
        .overlay {
            Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.calendarState.date = day
            model.calendarState.selectedDay = day
            model.settings.update { $0.calendarScope = .day }
        }
        .onTapGesture {
            model.calendarState.selectedDay = day
        }
        .contextMenu {
            Button("Neuer Termin …") {
                model.calendarState.newEventStart = model.calendarState.suggestedStart(on: day)
            }
            Button("Tag anzeigen") {
                model.calendarState.date = day
                model.settings.update { $0.calendarScope = .day }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (events.isEmpty ? ", keine Termine" : ", \(events.count) Termine"))
    }
}

#Preview("Hell") {
    MonthView(
        days: CalendarMath.monthGrid(containing: .now, calendar: .current),
        month: .now,
        events: PreviewData.calendar.events(in: CalendarMath.interval(for: .month, containing: .now, calendar: .current), hiddenCalendarIDs: [])
    )
    .environment(PreviewData.model())
    .frame(width: 900, height: 640)
}

#Preview("Dunkel") {
    MonthView(
        days: CalendarMath.monthGrid(containing: .now, calendar: .current),
        month: .now,
        events: PreviewData.calendar.events(in: CalendarMath.interval(for: .month, containing: .now, calendar: .current), hiddenCalendarIDs: [])
    )
    .environment(PreviewData.model())
    .frame(width: 900, height: 640)
    .preferredColorScheme(.dark)
}
