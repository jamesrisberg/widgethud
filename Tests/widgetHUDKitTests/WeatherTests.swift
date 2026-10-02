import Foundation
import XCTest
@testable import widgetHUDKit

final class WeatherTests: XCTestCase {
    /// A real Open-Meteo answer for Oslo (2026-10-01, hours trimmed), plus a missing hour.
    static let oslo = """
    {"latitude":59.906296,"longitude":10.744095,"utc_offset_seconds":7200,"timezone":"Europe/Oslo",
     "current":{"time":1790904600,"interval":900,"temperature_2m":15.7,"weather_code":3,"is_day":0},
     "hourly":{"time":[1790902800,1790906400,1790910000,1790913600],"temperature_2m":[15.8,15.6,null,14.3],
               "weather_code":[3,3,3,63],"is_day":[0,0,0,0]},
     "daily":{"time":[1790892000,1790978400,1791064800],"weather_code":[63,51,51],
              "temperature_2m_max":[16.3,16.0,14.5],"temperature_2m_min":[14.0,11.1,8.3]}}
    """

    func testParseForecast() throws {
        let fetched = Date(timeIntervalSince1970: 1_790_904_700)
        let r = try OpenMeteo.parseForecast(Data(Self.oslo.utf8), fetchedAt: fetched)
        XCTAssertEqual(r.timeZone, "Europe/Oslo")
        XCTAssertEqual(r.fetchedAt, fetched)
        XCTAssertEqual(r.current, .init(temperature: 15.7, code: 3, isDay: false))
        XCTAssertEqual(r.hourly.count, 3, "the hour without a temperature is skipped")
        XCTAssertEqual(r.hourly.last?.code, 63)
        XCTAssertEqual(r.daily.map(\.high), [16.3, 16.0, 14.5])
        XCTAssertEqual(r.today(now: fetched)?.low, 14.0)
        XCTAssertEqual(r.nextHours(5, now: fetched).first?.time, Date(timeIntervalSince1970: 1_790_902_800),
                       "the hour containing now comes first")
        XCTAssertEqual(r.nextDays(2, now: fetched).map(\.code), [63, 51])
        XCTAssertFalse(r.isOlder(than: 900, now: fetched.addingTimeInterval(899)))
        XCTAssertTrue(r.isOlder(than: 900, now: fetched.addingTimeInterval(900)))
    }

    func testParseErrors() {
        XCTAssertThrowsError(try OpenMeteo.parseForecast(Data(#"{"error":true,"reason":"Latitude must be in range"}"#.utf8))) {
            XCTAssertEqual($0 as? OpenMeteo.ParseError, .api("Latitude must be in range"))
        }
        XCTAssertThrowsError(try OpenMeteo.parseForecast(Data(#"{"hourly":{}}"#.utf8)))
    }

    func testReportCodableRoundTrip() throws {
        let r = try OpenMeteo.parseForecast(Data(Self.oslo.utf8), fetchedAt: Date(timeIntervalSince1970: 1_790_904_700))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = WeatherCache(url: dir.appendingPathComponent("weather-cache.json"))
        XCTAssertEqual(cache.load(), [:])
        try cache.save(["59.91,10.75": r])
        XCTAssertEqual(cache.load(), ["59.91,10.75": r])
    }

    func testURLs() {
        let url = OpenMeteo.forecastURL(GeoPoint(latitude: 59.91, longitude: 10.75)).absoluteString
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        for part in ["latitude=59.9100", "longitude=10.7500", "timezone=auto", "timeformat=unixtime", "forecast_days=6",
                     "current=temperature_2m,weather_code,is_day"] {
            XCTAssertTrue(url.contains(part), part)
        }
        XCTAssertEqual(OpenMeteo.searchURL("San José").absoluteString,
                       "https://geocoding-api.open-meteo.com/v1/search?name=San%20Jos%C3%A9&count=10&language=en&format=json")
    }

    func testSearchAndBestMatch() throws {
        let json = """
        {"results":[
          {"name":"Portland","latitude":45.52,"longitude":-122.68,"country":"United States","country_code":"US","admin1":"Oregon","timezone":"America/Los_Angeles"},
          {"name":"Portland","latitude":43.66,"longitude":-70.26,"country":"United States","country_code":"US","admin1":"Maine","timezone":"America/New_York"}]}
        """
        let places = try OpenMeteo.parseSearch(Data(json.utf8))
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[0].displayName, "Portland, Oregon, United States")
        XCTAssertEqual(GeoPlace.best(places, qualifiers: [])?.admin1, "Oregon")
        XCTAssertEqual(GeoPlace.best(places, qualifiers: ["maine"])?.admin1, "Maine")
        XCTAssertEqual(GeoPlace.best(places, qualifiers: ["Maine", "US"])?.admin1, "Maine")
        XCTAssertEqual(GeoPlace.best(places, qualifiers: ["Narnia"])?.admin1, "Oregon", "no match: the most relevant")
        XCTAssertEqual(try OpenMeteo.parseSearch(Data(#"{"generationtime_ms":0.1}"#.utf8)), [])
        let q = GeoPlace.query(" Portland , Maine ,")
        XCTAssertEqual(q.name, "Portland")
        XCTAssertEqual(q.qualifiers, ["Maine"])
        XCTAssertEqual(GeoPlace(name: "Oslo", admin1: "Oslo", country: "Norway", latitude: 0, longitude: 0).displayName, "Oslo, Norway")
    }

    func testClientWithAFakeFetch() async throws {
        let client = WeatherClient { url in
            if url.host == "geocoding-api.open-meteo.com" {
                XCTAssertTrue(url.absoluteString.contains("name=Oslo&"))
                return Data(#"{"results":[{"name":"Oslo","latitude":59.91,"longitude":10.75,"country":"Norway"}]}"#.utf8)
            }
            return Data(WeatherTests.oslo.utf8)
        }
        let found = try await client.lookUp("Oslo, Norway")
        XCTAssertEqual(found?.point, GeoPoint(latitude: 59.91, longitude: 10.75))
        let none = try await client.lookUp("  ")
        XCTAssertNil(none)
        let report = try await client.forecast(GeoPoint(latitude: 59.91, longitude: 10.75))
        XCTAssertEqual(report.current.code, 3)
    }

    func testConditions() {
        XCTAssertEqual(WeatherCondition(code: 0).symbol, "sun.max.fill")
        XCTAssertEqual(WeatherCondition(code: 0, isDay: false).symbol, "moon.stars.fill")
        XCTAssertEqual(WeatherCondition(code: 63).description, "Rain")
        XCTAssertEqual(WeatherCondition(code: 95).symbol, "cloud.bolt.fill")
        XCTAssertEqual(WeatherCondition(code: 1234).description, "Unknown")
        // Every WMO code Open-Meteo documents has words of its own.
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            XCTAssertNotEqual(WeatherCondition(code: code).description, "Unknown", "\(code)")
        }
    }

    func testGeoPointKeyAndValidity() {
        XCTAssertEqual(GeoPoint(latitude: 59.9139, longitude: 10.7522).key, "59.91,10.75")
        XCTAssertFalse(GeoPoint(latitude: 91, longitude: 0).isValid)
    }

    func testSampleWeatherIsCurrent() {
        let now = Date()
        let r = SampleData.weather(now: now)
        XCTAssertEqual(r.nextHours(5, now: now).count, 5)
        XCTAssertEqual(r.nextDays(5, now: now).count, 5)
        XCTAssertNotNil(r.today(now: now))
    }
}
