import Foundation

/// A clock instance's settings (Resources/clock.widget.json).
public struct ClockOptions: Equatable, Sendable {
    public enum Style: String, CaseIterable, Sendable {
        /// Analog when small, digital with the date when medium.
        case auto, analog, digital
    }

    /// The keys the schema lists.
    public static let keys: Set<String> = ["timeZone", "label", "style", "timeFormat", "seconds"]

    /// As entered: an identifier (`Europe/Oslo`), a city (`Oslo`, `new york`), an abbreviation
    /// (`UTC`, `PST`) or empty for this Mac's zone.
    public var timeZone: String
    public var label: String
    public var style: Style
    /// `12h`, `24h`, or anything else for the app's setting.
    public var timeFormat: String
    public var seconds: Bool

    public init(settings: [String: Any]) {
        timeZone = SettingReader.string(settings, "timeZone").trimmingCharacters(in: .whitespacesAndNewlines)
        label = SettingReader.string(settings, "label").trimmingCharacters(in: .whitespacesAndNewlines)
        style = Style(rawValue: SettingReader.string(settings, "style")) ?? .auto
        timeFormat = SettingReader.string(settings, "timeFormat", default: "app")
        seconds = SettingReader.bool(settings, "seconds", default: false)
    }

    /// The zone to show; `.current` for an empty setting; nil when the text names no zone.
    public func zone(current: TimeZone = .current) -> TimeZone? {
        timeZone.isEmpty ? current : Self.resolveZone(timeZone)
    }

    /// Whether the clock follows this Mac's zone (no `timeZone` set).
    public var isLocal: Bool { timeZone.isEmpty }

    /// `true` for analog at `small` under `auto`.
    public func isAnalog(small: Bool) -> Bool {
        switch style {
        case .analog: return true
        case .digital: return false
        case .auto: return small
        }
    }

    /// The label above the time: the setting, else the zone's city (`New York`; this Mac's for a
    /// local clock), else the text as typed (a zone that did not resolve).
    public func displayLabel(zone: TimeZone?, current: TimeZone = .current) -> String {
        if !label.isEmpty { return label }
        if isLocal { return Self.city(of: current) }
        return zone.map(Self.city(of:)) ?? timeZone
    }

    /// `"New York"` for America/New_York; the identifier for zones without a city (`GMT`).
    public static func city(of zone: TimeZone) -> String {
        let id = zone.identifier
        guard let last = id.split(separator: "/").last, id.contains("/") else { return id }
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Finds a zone from text: an exact identifier, a city (the identifier's last part, spaces
    /// for underscores, any case), or an abbreviation.
    public static func resolveZone(_ text: String) -> TimeZone? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let zone = TimeZone(identifier: text) { return zone }
        let wanted = text.lowercased().replacingOccurrences(of: "_", with: " ")
        if let id = TimeZone.knownTimeZoneIdentifiers.first(where: { $0.lowercased() == wanted.replacingOccurrences(of: " ", with: "_") }) {
            return TimeZone(identifier: id)
        }
        if let id = TimeZone.knownTimeZoneIdentifiers.first(where: {
            ($0.split(separator: "/").last.map(String.init) ?? $0).lowercased().replacingOccurrences(of: "_", with: " ") == wanted
        }) {
            return TimeZone(identifier: id)
        }
        return TimeZone(abbreviation: text.uppercased())
    }

    /// The zone's offset from `local` at `date`, `"+9h"`, `"-5h30"`; nil when they agree.
    public static func offsetLabel(_ zone: TimeZone, from local: TimeZone = .current, at date: Date = Date()) -> String? {
        let diff = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        guard diff != 0 else { return nil }
        let sign = diff > 0 ? "+" : "-"
        let minutes = abs(diff) / 60
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h)h\(String(format: "%02d", m))"
    }
}

/// A weather instance's settings (Resources/weather.widget.json), plus the coordinates widgetHUD
/// stores after looking the place up (keys the schema does not list).
public struct WeatherOptions: Equatable, Sendable {
    /// The keys the schema lists.
    public static let keys: Set<String> = ["place", "units", "showHourly", "showDaily"]
    /// Written by widgetHUD after a lookup (`HUDWidgetContext.updateSettings`), never shown.
    public static let resolvedKeys: Set<String> = ["latitude", "longitude", "resolvedPlace", "resolvedName"]

    public var place: String
    /// `celsius`, `fahrenheit`, or anything else for the app's setting.
    public var units: String
    public var showHourly: Bool
    public var showDaily: Bool
    public var latitude: Double?
    public var longitude: Double?
    /// The `place` text the coordinates were looked up for.
    public var resolvedPlace: String
    /// What the lookup found (`"Portland, Oregon, United States"`).
    public var resolvedName: String

    public init(settings: [String: Any]) {
        place = SettingReader.string(settings, "place").trimmingCharacters(in: .whitespacesAndNewlines)
        units = SettingReader.string(settings, "units", default: "app")
        showHourly = SettingReader.bool(settings, "showHourly", default: true)
        showDaily = SettingReader.bool(settings, "showDaily", default: true)
        latitude = SettingReader.double(settings, "latitude")
        longitude = SettingReader.double(settings, "longitude")
        resolvedPlace = SettingReader.string(settings, "resolvedPlace")
        resolvedName = SettingReader.string(settings, "resolvedName")
    }

    /// Where to fetch weather for: the stored coordinates, when they belong to the current place.
    public var point: GeoPoint? {
        guard !place.isEmpty, !needsLookup, let latitude, let longitude else { return nil }
        let p = GeoPoint(latitude: latitude, longitude: longitude)
        return p.isValid ? p : nil
    }

    /// A place is set but its coordinates are missing or were found for different text.
    public var needsLookup: Bool {
        guard !place.isEmpty else { return false }
        guard let latitude, let longitude, GeoPoint(latitude: latitude, longitude: longitude).isValid else { return true }
        return Self.normalized(resolvedPlace) != Self.normalized(place)
    }

    /// The short name to show: what the lookup found (its first part), else the text typed.
    public var displayName: String {
        let found = resolvedName.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return found.isEmpty ? place : found
    }

    /// The settings a successful lookup of `place` writes back.
    public static func resolution(for place: String, found: GeoPlace) -> [String: Any] {
        ["latitude": found.latitude, "longitude": found.longitude, "resolvedPlace": place, "resolvedName": found.displayName]
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0 == "," || $0.isWhitespace }).joined(separator: " ")
    }
}

/// A calendar instance's settings (Resources/calendar.widget.json).
public struct CalendarOptions: Equatable, Sendable {
    public static let keys: Set<String> = ["calendars", "daysAhead", "timeFormat"]
    public static let daysRange = 1...14

    /// Calendar names to show (any case); empty shows every calendar.
    public var calendars: [String]
    public var daysAhead: Int
    /// `12h`, `24h`, or anything else for the app's setting.
    public var timeFormat: String

    public init(settings: [String: Any]) {
        calendars = SettingReader.string(settings, "calendars").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        daysAhead = SettingReader.int(settings, "daysAhead", default: 3, range: Self.daysRange)
        timeFormat = SettingReader.string(settings, "timeFormat", default: "app")
    }

    public func includes(_ event: CalendarEvent) -> Bool {
        calendars.isEmpty || calendars.contains { $0.caseInsensitiveCompare(event.calendar) == .orderedSame }
    }
}
