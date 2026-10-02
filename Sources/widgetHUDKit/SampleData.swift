import Foundation

/// Made-up weather and events for `--snapshot` and `WIDGETHUD_SAMPLE_DATA=1`: offline, without
/// Calendar access, relative to `now` so they always look current.
public enum SampleData {
    public static let place = GeoPlace(name: "Oslo", admin1: "Oslo", country: "Norway", countryCode: "NO",
                                       latitude: 59.91, longitude: 10.75, timeZone: "Europe/Oslo")

    /// A sample place for any text: its name with Oslo's coordinates, nothing for empty text.
    public static func lookUp(_ text: String) -> GeoPlace? {
        let q = GeoPlace.query(text)
        guard !q.name.isEmpty else { return nil }
        var p = place
        p.name = q.name.prefix(1).uppercased() + q.name.dropFirst()
        p.admin1 = q.qualifiers.first
        p.country = q.qualifiers.dropFirst().first
        return p
    }

    public static func weather(now: Date = Date(), zone: TimeZone = .current) -> WeatherReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let temps: [Double] = [14, 15, 16, 16, 15, 13, 12, 11, 10, 10, 9, 9]
        let codes = [2, 2, 1, 0, 0, 2, 3, 61, 63, 61, 3, 3]
        let hours = temps.indices.map { i in
            let t = hourStart.addingTimeInterval(Double(i) * 3600)
            let h = calendar.component(.hour, from: t)
            return WeatherReport.Hour(time: t, temperature: temps[i], code: codes[i], isDay: (7..<19).contains(h))
        }
        let today = calendar.startOfDay(for: now)
        let days: [(Double, Double, Int)] = [(17, 9, 2), (14, 8, 61), (12, 6, 63), (15, 7, 2), (18, 10, 0), (16, 9, 3)]
        let daily = days.enumerated().map { i, d in
            WeatherReport.Day(date: calendar.date(byAdding: .day, value: i, to: today) ?? today, high: d.0, low: d.1, code: d.2)
        }
        return WeatherReport(fetchedAt: now, timeZone: zone.identifier,
                             current: .init(temperature: 14.4, code: 2, isDay: hours[0].isDay), hourly: hours, daily: daily)
    }

    public static func events(now: Date = Date(), calendar: Calendar = .current) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }
        let soon = now.addingTimeInterval(25 * 60)
        return [
            CalendarEvent(id: "s1", title: "Design review", start: soon, end: soon.addingTimeInterval(3600),
                          calendar: "Work", color: "#4F8DF7"),
            CalendarEvent(id: "s2", title: "Lunch with Ana", start: soon.addingTimeInterval(3 * 3600),
                          end: soon.addingTimeInterval(4 * 3600), calendar: "Home", color: "#F2A541"),
            CalendarEvent(id: "s3", title: "Ship widgetHUD", start: today, end: at(1, 0), isAllDay: true,
                          calendar: "Work", color: "#4F8DF7"),
            CalendarEvent(id: "s4", title: "Climbing", start: at(1, 18), end: at(1, 20), calendar: "Home", color: "#F2A541"),
            CalendarEvent(id: "s5", title: "1:1 with Sam", start: at(1, 9, 30), end: at(1, 10), calendar: "Work", color: "#4F8DF7"),
            CalendarEvent(id: "s6", title: "Dentist", start: at(2, 8), end: at(2, 9), calendar: "Home", color: "#F2A541"),
            CalendarEvent(id: "s7", title: "Team offsite", start: at(2, 10), end: at(2, 16), calendar: "Work", color: "#4F8DF7"),
        ]
    }
}
