import Foundation

/// One calendar event, as the calendar widget needs it (filled from EventKit in the app, or from
/// sample data).
public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The calendar's title (what the `calendars` setting matches).
    public var calendar: String
    /// The calendar's colour, `#RRGGBB`.
    public var color: String?
    public var location: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendar: String,
                color: String? = nil, location: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.color = color
        self.location = location
    }

    public func isHappening(at now: Date) -> Bool { start <= now && now < end }
}

/// Whether widgetHUD may read the user's calendars (EventKit's authorization, simplified).
public enum CalendarAccess: String, Codable, Sendable {
    /// Never asked: widgetHUD asks when the first calendar widget appears.
    case notDetermined
    case granted
    /// Refused by the user (or only add-events access, which cannot read).
    case denied
    /// Blocked by a profile or parental controls.
    case restricted
}

/// Picks and groups events for the calendar widget's sizes.
public enum Agenda {
    /// Events that have not ended by `now`, starting before `limitDate`, all-day events of a day
    /// before its timed ones, then by start and title.
    public static func upcoming(_ events: [CalendarEvent], now: Date, until limitDate: Date,
                                calendar: Calendar = .current) -> [CalendarEvent] {
        events.filter { $0.end > now && $0.start < limitDate }
            .sorted { a, b in
                let da = calendar.startOfDay(for: max(a.start, now)), db = calendar.startOfDay(for: max(b.start, now))
                if da != db { return da < db }
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                if a.start != b.start { return a.start < b.start }
                return a.title < b.title
            }
    }

    /// The event a one-event view shows: the next timed event (a meeting in 25 minutes says
    /// more than today's all-day event), else the first all-day one.
    public static func next(_ upcoming: [CalendarEvent]) -> CalendarEvent? {
        upcoming.first { !$0.isAllDay } ?? upcoming.first
    }

    /// The end of the window `days` days long that starts today (midnight after the last day).
    public static func horizon(days: Int, now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: max(days, 1), to: calendar.startOfDay(for: now)) ?? now
    }

    public struct Day: Equatable, Sendable {
        /// Midnight starting the day.
        public var date: Date
        public var events: [CalendarEvent]
    }

    /// Today and the following days (`days` in all), each with the events that overlap it and
    /// have not ended by `now`. Days without events are left out, except today.
    public static func days(_ events: [CalendarEvent], now: Date, days: Int, calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var out: [Day] = []
        for offset in 0..<max(days, 1) {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let dayEvents = upcoming(events.filter { $0.start < end && $0.end > start && $0.end > now },
                                     now: max(now, start), until: end, calendar: calendar)
            if offset == 0 || !dayEvents.isEmpty { out.append(Day(date: start, events: dayEvents)) }
        }
        return out
    }

    /// `"Today"`, `"Tomorrow"`, else `"Fri 3 Oct"`.
    public static func dayTitle(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d MMM"
        return f.string(from: day)
    }

    /// When an event is, relative to `now`: `"Now"`, `"In 25 min"`, `"All day"`, `"14:00"`,
    /// `"Tomorrow 9:00 AM"`, `"Fri 14:00"`.
    public static func when(_ event: CalendarEvent, now: Date, format: TimeFormat, calendar: Calendar = .current) -> String {
        if event.isAllDay {
            if event.start <= now { return "All day" }
            return calendar.isDate(event.start, inSameDayAs: now) ? "All day" : "\(dayTitle(event.start, now: now, calendar: calendar)), all day"
        }
        if event.isHappening(at: now) { return "Now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "In \(max(minutes, 1)) min" }
        let time = format.time(event.start, zone: calendar.timeZone)
        if calendar.isDate(event.start, inSameDayAs: now) { return time }
        return "\(dayTitle(event.start, now: now, calendar: calendar).split(separator: " ").first.map(String.init) ?? "") \(time)"
    }

    /// An event's time in the agenda: `"All day"` or its start (`"14:00"`).
    public static func span(_ event: CalendarEvent, format: TimeFormat, calendar: Calendar = .current) -> String {
        if event.isAllDay { return "All day" }
        return format.time(event.start, zone: calendar.timeZone)
    }
}
