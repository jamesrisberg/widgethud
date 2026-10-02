import Foundation

/// A point on the globe, rounded for cache keys and request sharing.
public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Two instances for the same city share one forecast: coordinates to two decimals (~1 km).
    public var key: String { String(format: "%.2f,%.2f", latitude, longitude) }

    public var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

/// A forecast, temperatures in Celsius.
public struct WeatherReport: Codable, Equatable, Sendable {
    public struct Current: Codable, Equatable, Sendable {
        public var temperature: Double
        public var code: Int
        public var isDay: Bool
        public init(temperature: Double, code: Int, isDay: Bool) {
            self.temperature = temperature
            self.code = code
            self.isDay = isDay
        }
    }

    public struct Hour: Codable, Equatable, Sendable {
        public var time: Date
        public var temperature: Double
        public var code: Int
        public var isDay: Bool
        public init(time: Date, temperature: Double, code: Int, isDay: Bool) {
            self.time = time
            self.temperature = temperature
            self.code = code
            self.isDay = isDay
        }
    }

    public struct Day: Codable, Equatable, Sendable {
        /// Local midnight of the day, in the place's time zone.
        public var date: Date
        public var high: Double
        public var low: Double
        public var code: Int
        public init(date: Date, high: Double, low: Double, code: Int) {
            self.date = date
            self.high = high
            self.low = low
            self.code = code
        }
    }

    public var fetchedAt: Date
    /// The place's time zone identifier (`Europe/Oslo`): hours and weekdays are shown in it.
    public var timeZone: String
    public var current: Current
    public var hourly: [Hour]
    public var daily: [Day]

    public init(fetchedAt: Date, timeZone: String, current: Current, hourly: [Hour], daily: [Day]) {
        self.fetchedAt = fetchedAt
        self.timeZone = timeZone
        self.current = current
        self.hourly = hourly
        self.daily = daily
    }

    public var zone: TimeZone { TimeZone(identifier: timeZone) ?? .current }

    /// Today's forecast (the day containing `now` in the place's zone), else the first day.
    public func today(now: Date = Date()) -> Day? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return daily.first { calendar.isDate($0.date, inSameDayAs: now) } ?? daily.first
    }

    /// The next `count` hours, starting with the hour containing `now`.
    public func nextHours(_ count: Int, now: Date = Date()) -> [Hour] {
        Array(hourly.filter { $0.time.addingTimeInterval(3600) > now }.prefix(count))
    }

    /// The next `count` days, starting today.
    public func nextDays(_ count: Int, now: Date = Date()) -> [Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        return Array(daily.filter { $0.date >= today || calendar.isDate($0.date, inSameDayAs: now) }.prefix(count))
    }

    /// Whether the report is due for a refresh.
    public func isOlder(than interval: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) >= interval
    }
}

/// A WMO weather interpretation code (what Open-Meteo reports) as a symbol and words.
public struct WeatherCondition: Equatable, Sendable {
    public var code: Int
    public var isDay: Bool

    public init(code: Int, isDay: Bool = true) {
        self.code = code
        self.isDay = isDay
    }

    /// An SF Symbol (multicolour-capable `.fill` variants).
    public var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    public var description: String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm, hail"
        default: return "Unknown"
        }
    }
}

/// A geocoded place (Open-Meteo's geocoding API).
public struct GeoPlace: Codable, Equatable, Sendable {
    public var name: String
    public var admin1: String?
    public var country: String?
    public var countryCode: String?
    public var latitude: Double
    public var longitude: Double
    public var timeZone: String?

    public init(name: String, admin1: String? = nil, country: String? = nil, countryCode: String? = nil,
                latitude: Double, longitude: Double, timeZone: String? = nil) {
        self.name = name
        self.admin1 = admin1
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
    }

    public var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    /// `"Portland, Oregon, United States"`.
    public var displayName: String {
        [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.reduce(into: [String]()) { parts, part in
            if !parts.contains(part) { parts.append(part) }
        }.joined(separator: ", ")
    }

    /// The search a free-text place turns into: the name to look up (before the first comma) and
    /// the qualifiers after it that pick among same-named places (`"Portland, Maine"`).
    public static func query(_ text: String) -> (name: String, qualifiers: [String]) {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (parts.first ?? "", Array(parts.dropFirst()))
    }

    /// The best of `results` (in Open-Meteo's relevance order) for the qualifiers: the first
    /// whose region, country or country code matches every qualifier, else the first result.
    public static func best(_ results: [GeoPlace], qualifiers: [String]) -> GeoPlace? {
        guard !qualifiers.isEmpty else { return results.first }
        func matches(_ place: GeoPlace, _ q: String) -> Bool {
            let q = q.lowercased()
            return [place.admin1, place.country, place.countryCode].compactMap { $0?.lowercased() }
                .contains { $0 == q || $0.hasPrefix(q) }
        }
        return results.first { place in qualifiers.allSatisfy { matches(place, $0) } } ?? results.first
    }
}

/// Open-Meteo's forecast and geocoding APIs (no key; https://open-meteo.com).
public enum OpenMeteo {
    public static let forecastDays = 6
    public static let forecastHours = 24

    public static func forecastURL(_ point: GeoPoint) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", point.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", point.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "forecast_hours", value: String(forecastHours)),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return c.url!
    }

    public static func searchURL(_ name: String, count: Int = 10) -> URL {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url!
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case malformed(String)
        case api(String)

        public var description: String {
            switch self {
            case .malformed(let what): return "unexpected weather data (\(what))"
            case .api(let reason): return reason
            }
        }
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var weather_code: Int
            var is_day: Int?
        }
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]
            var weather_code: [Int?]
            var is_day: [Int?]?
        }
        struct Daily: Decodable {
            var time: [Double]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
        }
        var timezone: String?
        var current: Current
        var hourly: Hourly?
        var daily: Daily?
    }

    private struct APIError: Decodable {
        var error: Bool
        var reason: String?
    }

    /// Parses a forecast response (`timeformat=unixtime`). Hours or days with missing values are
    /// skipped; a missing `current` block is an error.
    public static func parseForecast(_ data: Data, fetchedAt: Date = Date()) throws -> WeatherReport {
        if let error = try? JSONDecoder().decode(APIError.self, from: data), error.error {
            throw ParseError.api(error.reason ?? "Open-Meteo refused the request")
        }
        let r: ForecastResponse
        do { r = try JSONDecoder().decode(ForecastResponse.self, from: data) } catch {
            throw ParseError.malformed("\(error)")
        }
        var hours: [WeatherReport.Hour] = []
        if let h = r.hourly {
            for (i, t) in h.time.enumerated() {
                guard i < h.temperature_2m.count, i < h.weather_code.count,
                      let temp = h.temperature_2m[i], let code = h.weather_code[i] else { continue }
                let day = (h.is_day.flatMap { i < $0.count ? $0[i] : nil }) ?? 1
                hours.append(.init(time: Date(timeIntervalSince1970: t), temperature: temp, code: code, isDay: day != 0))
            }
        }
        var days: [WeatherReport.Day] = []
        if let d = r.daily {
            for (i, t) in d.time.enumerated() {
                guard i < d.weather_code.count, i < d.temperature_2m_max.count, i < d.temperature_2m_min.count,
                      let code = d.weather_code[i], let high = d.temperature_2m_max[i], let low = d.temperature_2m_min[i] else { continue }
                days.append(.init(date: Date(timeIntervalSince1970: t), high: high, low: low, code: code))
            }
        }
        return WeatherReport(fetchedAt: fetchedAt, timeZone: r.timezone ?? TimeZone.current.identifier,
                             current: .init(temperature: r.current.temperature_2m, code: r.current.weather_code,
                                            isDay: (r.current.is_day ?? 1) != 0),
                             hourly: hours, daily: days)
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
            var country_code: String?
            var admin1: String?
            var timezone: String?
        }
        var results: [Result]?
    }

    /// Parses a geocoding response; no `results` is an empty list.
    public static func parseSearch(_ data: Data) throws -> [GeoPlace] {
        if let error = try? JSONDecoder().decode(APIError.self, from: data), error.error {
            throw ParseError.api(error.reason ?? "Open-Meteo refused the request")
        }
        let r: SearchResponse
        do { r = try JSONDecoder().decode(SearchResponse.self, from: data) } catch {
            throw ParseError.malformed("\(error)")
        }
        return (r.results ?? []).map {
            GeoPlace(name: $0.name, admin1: $0.admin1, country: $0.country, countryCode: $0.country_code,
                     latitude: $0.latitude, longitude: $0.longitude, timeZone: $0.timezone)
        }
    }
}

/// Fetches forecasts and looks up places. `fetch` is injectable so tests run offline.
public struct WeatherClient: Sendable {
    public var fetch: @Sendable (URL) async throws -> Data

    public init(fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.fetch = fetch
    }

    /// URLSession with a short timeout; non-2xx answers with Open-Meteo's `reason` when it gives one.
    public static let live = WeatherClient { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("widgetHUD (MacHUD widget set)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let error = try? JSONDecoder().decode([String: String].self, from: data), let reason = error["reason"] {
                throw OpenMeteo.ParseError.api(reason)
            }
            throw OpenMeteo.ParseError.api("Open-Meteo answered \(http.statusCode)")
        }
        return data
    }

    public func forecast(_ point: GeoPoint, now: Date = Date()) async throws -> WeatherReport {
        try OpenMeteo.parseForecast(try await fetch(OpenMeteo.forecastURL(point)), fetchedAt: now)
    }

    /// The best place for free text (`"Portland, Maine"`); nil when nothing matches.
    public func lookUp(_ text: String) async throws -> GeoPlace? {
        let q = GeoPlace.query(text)
        guard !q.name.isEmpty else { return nil }
        return GeoPlace.best(try await search(q.name), qualifiers: q.qualifiers)
    }

    public func search(_ name: String) async throws -> [GeoPlace] {
        try OpenMeteo.parseSearch(try await fetch(OpenMeteo.searchURL(name)))
    }
}

/// The last forecast per place, on disk so widgets show something at launch and offline.
public struct WeatherCache: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [String: WeatherReport] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([String: WeatherReport].self, from: data)) ?? [:]
    }

    public func save(_ reports: [String: WeatherReport]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(reports).write(to: url, options: .atomic)
    }
}
