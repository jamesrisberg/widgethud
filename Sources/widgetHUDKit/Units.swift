import Foundation

/// Celsius or Fahrenheit. Weather is fetched and cached in Celsius and converted for display.
public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius, fahrenheit

    /// The app-wide setting: a unit, or `auto` (the Mac's region and temperature preference).
    public enum Preference: String, Codable, CaseIterable, Sendable {
        case auto, celsius, fahrenheit
    }

    public var symbol: String { self == .celsius ? "°C" : "°F" }

    public func convert(celsius value: Double) -> Double {
        self == .celsius ? value : value * 9 / 5 + 32
    }

    /// `value` (Celsius) in this unit, rounded to a whole degree: `"16°"`.
    public func format(celsius value: Double) -> String {
        let converted = convert(celsius: value).rounded()
        // Avoid "-0°" for values that round to zero from below.
        return "\(converted == 0 ? 0 : Int(converted))°"
    }

    /// The unit a region uses: the user's explicit choice in System Settings (`AppleTemperatureUnit`,
    /// "Celsius" or "Fahrenheit") when there is one, else Fahrenheit for the US measurement system.
    public static func regional(locale: Locale = .current,
                                preference: String? = UserDefaults.standard.string(forKey: "AppleTemperatureUnit")) -> TemperatureUnit {
        switch preference?.lowercased() {
        case "fahrenheit": return .fahrenheit
        case "celsius": return .celsius
        default: return locale.measurementSystem == .us ? .fahrenheit : .celsius
        }
    }

    /// The unit for a widget: its own setting (`celsius`/`fahrenheit`), else the app's (`auto`
    /// reads the region). Unknown instance values (`app`, empty) fall through to the app.
    public static func resolve(instance: String?, app: Preference, regional: @autoclosure () -> TemperatureUnit) -> TemperatureUnit {
        if let instance, let unit = TemperatureUnit(rawValue: instance) { return unit }
        switch app {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        case .auto: return regional()
        }
    }
}

/// 12- or 24-hour clock times.
public enum TimeFormat: String, Codable, CaseIterable, Sendable {
    case twelve = "12h"
    case twentyFour = "24h"

    /// The app-wide setting: a format, or `auto` (the Mac's region).
    public enum Preference: String, Codable, CaseIterable, Sendable {
        case auto
        case twelve = "12h"
        case twentyFour = "24h"
    }

    public var is24Hour: Bool { self == .twentyFour }

    /// What the region uses: 12-hour when its hour format has an AM/PM marker.
    public static func regional(locale: Locale = .current) -> TimeFormat {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        return pattern.contains("a") ? .twelve : .twentyFour
    }

    /// A widget's own setting (`12h`/`24h`), else the app's (`auto` reads the region).
    public static func resolve(instance: String?, app: Preference, regional: @autoclosure () -> TimeFormat) -> TimeFormat {
        if let instance, let format = TimeFormat(rawValue: instance) { return format }
        switch app {
        case .twelve: return .twelve
        case .twentyFour: return .twentyFour
        case .auto: return regional()
        }
    }

    /// `"14:05"` / `"2:05 PM"` (with seconds: `"14:05:09"`), in `zone`.
    public func time(_ date: Date, zone: TimeZone = .current, seconds: Bool = false, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        switch (self, seconds) {
        case (.twentyFour, false): formatter.dateFormat = "H:mm"
        case (.twentyFour, true): formatter.dateFormat = "H:mm:ss"
        case (.twelve, false): formatter.dateFormat = "h:mm a"
        case (.twelve, true): formatter.dateFormat = "h:mm:ss a"
        }
        return formatter.string(from: date)
    }

    /// An hour label for forecasts: `"14"` / `"2 PM"`, in `zone`.
    public func hour(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = self == .twentyFour ? "HH" : "h a"
        return formatter.string(from: date)
    }
}

/// Reads one instance setting leniently from its JSON value (`HUDSettingValue.jsonValue`):
/// MacHUD validates against the schema, but keys the schema does not list arrive unchecked and a
/// hand-written `widget create` can send anything.
public enum SettingReader {
    public static func string(_ settings: [String: Any], _ key: String, default fallback: String = "") -> String {
        switch settings[key] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return fallback
        }
    }

    public static func bool(_ settings: [String: Any], _ key: String, default fallback: Bool) -> Bool {
        switch settings[key] {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: return fallback
            }
        default: return fallback
        }
    }

    public static func double(_ settings: [String: Any], _ key: String) -> Double? {
        switch settings[key] {
        case let d as Double: return d.isFinite ? d : nil
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    public static func int(_ settings: [String: Any], _ key: String, default fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let d = double(settings, key) else { return fallback }
        return min(max(Int(d.rounded()), range.lowerBound), range.upperBound)
    }
}

/// How long ago something happened, short: `"just now"`, `"12 min ago"`, `"3 h ago"`, `"2 d ago"`.
public enum Age {
    public static func text(since date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60)) min ago"
        case ..<86_400: return "\(Int(s / 3600)) h ago"
        default: return "\(Int(s / 86_400)) d ago"
        }
    }
}
