import Foundation

/// widgetHUD's app-wide settings: the defaults every widget falls back to (Resources/settings.json),
/// persisted as JSON in `<home>/preferences.json`. Values arrive over the socket as strings
/// (`settings set k=v`), so `applying(_:)` parses and validates them all before changing anything.
/// Each widget instance has its own settings on top (the `*.widget.json` schemas); an instance
/// setting of `app` means "use these".
public struct AppSettings: Codable, Equatable, Sendable {
    public var temperatureUnit: TemperatureUnit.Preference
    public var timeFormat: TimeFormat.Preference

    public init(temperatureUnit: TemperatureUnit.Preference = .auto, timeFormat: TimeFormat.Preference = .auto) {
        self.temperatureUnit = temperatureUnit
        self.timeFormat = timeFormat
    }

    /// The keys `settings get` reports and `settings set` accepts (Resources/settings.json).
    public static let keys: Set<String> = ["temperatureUnit", "timeFormat"]

    /// Saved values are merged over the defaults key by key: a key missing from
    /// `preferences.json` (written before the setting existed) or one that does not decode
    /// keeps its default, and every other saved value is kept.
    /// Add each new field here with `Self.value(_:_:default:)`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        temperatureUnit = Self.value(c, .temperatureUnit, default: d.temperatureUnit)
        timeFormat = Self.value(c, .timeFormat, default: d.timeFormat)
    }

    private static func value<T: Decodable, K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K, default fallback: T) -> T {
        ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    public enum SettingsError: Error, Equatable, CustomStringConvertible {
        case unknownKey(String)
        case invalid(key: String, value: String)

        public var description: String {
            switch self {
            case .unknownKey(let key): return "unknown setting \(key)"
            case .invalid(let key, let value): return "invalid value \(value) for \(key)"
            }
        }
    }

    /// The settings with `values` applied; throws on the first unknown key or bad value.
    public func applying(_ values: [String: String]) throws -> AppSettings {
        var next = self
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            switch key {
            case "temperatureUnit":
                guard let unit = TemperatureUnit.Preference(rawValue: value) else { throw SettingsError.invalid(key: key, value: value) }
                next.temperatureUnit = unit
            case "timeFormat":
                guard let format = TimeFormat.Preference(rawValue: value) else { throw SettingsError.invalid(key: key, value: value) }
                next.timeFormat = format
            default:
                throw SettingsError.unknownKey(key)
            }
        }
        return next
    }

    /// `settings get`'s payload.
    public var json: [String: Any] { ["temperatureUnit": temperatureUnit.rawValue, "timeFormat": timeFormat.rawValue] }

    // MARK: Persistence

    /// Reads the settings at `url`, saved values over the defaults (see `init(from:)`); defaults
    /// when the file is missing or not a JSON object.
    public static func load(from url: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
