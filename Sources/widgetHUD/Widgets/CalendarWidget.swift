import HUDKit
import SwiftUI
import widgetHUDKit

/// The calendar widget (EventKit): small (today's date and the next event), medium (the next
/// three events), large (an agenda for the days ahead). widgetHUD asks for Calendar access when
/// the first calendar widget appears; without it the widget says so and offers the fix.
struct CalendarWidget: View {
    @ObservedObject var context: HUDWidgetContext
    @ObservedObject var model: AppModel
    @ObservedObject var calendar: CalendarStore

    var body: some View {
        content
            .onAppear { calendar.activate() }
    }

    @ViewBuilder
    private var content: some View {
        let compact = context.size == .small
        switch calendar.access {
        case .granted:
            let options = CalendarOptions(settings: context.jsonSettings)
            // Redrawn every minute: "In 25 min" and events that ended move on.
            TimelineView(.periodic(from: ClockWidget.minuteStart(), by: 60)) { timeline in
                CalendarContent(events: calendar.events.filter(options.includes), options: options,
                                format: model.timeFormat(instance: options.timeFormat), size: context.size, now: timeline.date)
            }
        case .notDetermined:
            WidgetMessage(symbol: "calendar.badge.exclamationmark", title: "Calendar access needed",
                          detail: compact ? nil : "widgetHUD shows your events once you allow it to read your calendars.",
                          button: "Allow…", compact: compact, action: { calendar.requestAccess() })
        case .denied:
            WidgetMessage(symbol: "calendar.badge.exclamationmark", title: "No Calendar access",
                          detail: compact ? "Turn on widgetHUD in Settings." : "Turn on widgetHUD in Privacy & Security › Calendars.",
                          button: "Open Settings…", compact: compact, action: { calendar.openPrivacySettings() })
        case .restricted:
            WidgetMessage(symbol: "lock", title: "Calendar access is restricted",
                          detail: compact ? nil : "A profile or Screen Time setting on this Mac blocks it.", compact: compact)
        }
    }
}

private struct CalendarContent: View {
    let events: [CalendarEvent]
    let options: CalendarOptions
    let format: TimeFormat
    let size: HUDWidgetSize
    let now: Date

    private var horizon: Date { Agenda.horizon(days: options.daysAhead, now: now) }
    private var upcoming: [CalendarEvent] { Agenda.upcoming(events, now: now, until: horizon) }

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        default: large
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateBlock(daySize: 38)
            Spacer(minLength: 4)
            if let next = Agenda.next(upcoming) {
                EventRow(event: next, when: Agenda.when(next, now: now, format: format), lines: 2)
            } else {
                Text(emptyText).font(.system(size: 12)).foregroundStyle(WidgetLook.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WidgetLook.padding)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            dateBlock(daySize: 44).frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                let next = Array(upcoming.prefix(3))
                if next.isEmpty {
                    Spacer(minLength: 0)
                    Text(emptyText).font(.system(size: 13)).foregroundStyle(WidgetLook.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(next) { EventRow(event: $0, when: Agenda.when($0, now: now, format: format), lines: 1) }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WidgetLook.padding)
    }

    /// Rows that fit the large size: day headers and events, cut off with "+n more".
    private static let largeRows = 11

    private var large: some View {
        let days = Agenda.days(events, now: now, days: options.daysAhead)
        var rows: [AgendaRow] = []
        for day in days {
            rows.append(.header(day.date))
            if day.events.isEmpty { rows.append(.empty) }
            rows += day.events.map(AgendaRow.event)
        }
        let shown = rows.count > Self.largeRows ? Array(rows.prefix(Self.largeRows - 1)) : rows
        let hidden = rows.dropFirst(shown.count).filter { if case .event = $0 { return true } else { return false } }.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.text(now, "EEEE").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetLook.accent)
                Text(Self.text(now, "d MMMM"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetLook.primary)
            }
            .padding(.bottom, 2)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                switch row {
                case .header(let date):
                    Text(Agenda.dayTitle(date, now: now))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetLook.secondary)
                        .padding(.top, 3)
                case .empty:
                    Text("Nothing more today").font(.system(size: 12)).foregroundStyle(WidgetLook.tertiary)
                case .event(let event):
                    AgendaEventRow(event: event, time: Agenda.span(event, format: format), now: now)
                }
            }
            if hidden > 0 {
                Text("+\(hidden) more").font(.system(size: 11, weight: .medium)).foregroundStyle(WidgetLook.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WidgetLook.padding + 2)
    }

    private enum AgendaRow {
        case header(Date), empty, event(CalendarEvent)
    }

    private var emptyText: String {
        options.daysAhead == 1 ? "Nothing more today" : "Nothing in the next \(options.daysAhead) days"
    }

    private func dateBlock(daySize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(Self.text(now, "EEEE").uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WidgetLook.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Self.text(now, "d"))
                .font(.system(size: daySize, weight: .light, design: .rounded))
                .foregroundStyle(WidgetLook.primary)
        }
    }

    static func text(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }
}

/// An event with its calendar colour, title and when.
private struct EventRow: View {
    let event: CalendarEvent
    let when: String
    let lines: Int

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: event.color) ?? WidgetLook.secondary)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetLook.primary)
                    .lineLimit(lines)
                Text(when)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetLook.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An agenda line: time, colour dot, title.
private struct AgendaEventRow: View {
    let event: CalendarEvent
    let time: String
    let now: Date

    var body: some View {
        HStack(spacing: 7) {
            Text(time)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(event.isHappening(at: now) ? WidgetLook.accent : WidgetLook.secondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Circle().fill(Color(hex: event.color) ?? WidgetLook.secondary).frame(width: 6, height: 6)
            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetLook.primary)
                .lineLimit(1)
        }
    }
}
