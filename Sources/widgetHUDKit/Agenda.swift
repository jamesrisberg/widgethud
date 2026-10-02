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

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendar: String,
                color: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.color = color
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

    /// The locale's words for today and tomorrow (`"Today"`, `"I morgen"`), else its short
    /// weekday and date (`"Sat, Oct 3"`, `"lør. 3. okt."`).
    public static func dayTitle(_ day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if let relative = relativeDay(day, now: now, calendar: calendar, locale: locale) { return relative }
        return format(day, template: "EEEdMMM", calendar: calendar, locale: locale)
    }

    /// When an event is, relative to `now`: `"Now"`, `"In 25 min"`, `"All day"`, `"14:00"`,
    /// `"Tomorrow 9:00 AM"`, `"Sat 14:00"` (day words and times in the locale's language).
    public static func when(_ event: CalendarEvent, now: Date, format: TimeFormat, calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        if event.isAllDay {
            if event.start <= now || calendar.isDate(event.start, inSameDayAs: now) { return "All day" }
            return "\(dayTitle(event.start, now: now, calendar: calendar, locale: locale)), all day"
        }
        if event.isHappening(at: now) { return "Now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "In \(max(minutes, 1)) min" }
        let time = format.time(event.start, zone: calendar.timeZone, locale: locale)
        if calendar.isDate(event.start, inSameDayAs: now) { return time }
        let day = relativeDay(event.start, now: now, calendar: calendar, locale: locale)
            ?? Self.format(event.start, template: "EEE", calendar: calendar, locale: locale)
        return "\(day) \(time)"
    }

    /// An event's time in the agenda: `"All day"` or its start (`"14:00"`).
    public static func span(_ event: CalendarEvent, format: TimeFormat, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if event.isAllDay { return "All day" }
        return format.time(event.start, zone: calendar.timeZone, locale: locale)
    }

    /// The locale's word for `day` when it is today or tomorrow (`"Today"`, `"I morgen"`); nil otherwise.
    public static func relativeDay(_ day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day
        guard let offset, offset == 0 || offset == 1 else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.calendar = calendar
        f.dateTimeStyle = .named
        let word = f.localizedString(from: DateComponents(day: offset))
        return word.prefix(1).uppercased(with: locale) + word.dropFirst()
    }

    static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }
}
