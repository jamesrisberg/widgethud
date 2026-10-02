import Foundation
import XCTest
@testable import widgetHUDKit

final class UnitsTests: XCTestCase {
    func testTemperatureConversionAndFormat() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(celsius: 100), 212)
        XCTAssertEqual(TemperatureUnit.celsius.format(celsius: 14.6), "15°")
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius: 14.4), "58°")
        XCTAssertEqual(TemperatureUnit.celsius.format(celsius: -0.3), "0°", "no negative zero")
        XCTAssertEqual(TemperatureUnit.celsius.format(celsius: -3.6), "-4°")
    }

    func testTemperatureRegionalHonoursTheExplicitPreferenceFirst() {
        let us = Locale(identifier: "en_US"), no = Locale(identifier: "nb_NO")
        XCTAssertEqual(TemperatureUnit.regional(locale: us, preference: nil), .fahrenheit)
        XCTAssertEqual(TemperatureUnit.regional(locale: no, preference: nil), .celsius)
        XCTAssertEqual(TemperatureUnit.regional(locale: us, preference: "Celsius"), .celsius)
        XCTAssertEqual(TemperatureUnit.regional(locale: no, preference: "Fahrenheit"), .fahrenheit)
    }

    func testTemperatureResolveInstanceThenAppThenRegion() {
        XCTAssertEqual(TemperatureUnit.resolve(instance: "celsius", app: .fahrenheit, regional: .fahrenheit), .celsius)
        XCTAssertEqual(TemperatureUnit.resolve(instance: "app", app: .fahrenheit, regional: .celsius), .fahrenheit)
        XCTAssertEqual(TemperatureUnit.resolve(instance: nil, app: .auto, regional: .celsius), .celsius)
        XCTAssertEqual(TemperatureUnit.resolve(instance: "", app: .auto, regional: .fahrenheit), .fahrenheit)
    }

    func testTimeFormatResolveAndRegional() {
        XCTAssertEqual(TimeFormat.regional(locale: Locale(identifier: "en_US")), .twelve)
        XCTAssertEqual(TimeFormat.regional(locale: Locale(identifier: "en_GB")), .twentyFour)
        XCTAssertEqual(TimeFormat.resolve(instance: "24h", app: .twelve, regional: .twelve), .twentyFour)
        XCTAssertEqual(TimeFormat.resolve(instance: "app", app: .twelve, regional: .twentyFour), .twelve)
        XCTAssertEqual(TimeFormat.resolve(instance: nil, app: .auto, regional: .twentyFour), .twentyFour)
    }

    func testTimeFormatting() {
        let utc = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 14 * 3600 + 5 * 60 + 9)
        XCTAssertEqual(TimeFormat.twentyFour.time(date, zone: utc), "14:05")
        XCTAssertEqual(TimeFormat.twentyFour.time(date, zone: utc, seconds: true), "14:05:09")
        XCTAssertEqual(TimeFormat.twelve.time(date, zone: utc), "2:05 PM")
        XCTAssertEqual(TimeFormat.twelve.time(date, zone: TimeZone(identifier: "Asia/Tokyo")!), "11:05 PM")
        XCTAssertEqual(TimeFormat.twentyFour.hour(date, zone: utc), "14")
        XCTAssertEqual(TimeFormat.twelve.hour(date, zone: utc), "2 PM")
    }

    func testSettingReaderIsLenient() {
        let s: [String: Any] = ["b1": true, "b2": "off", "n": 3.6, "ns": "2.5", "s": 7, "bad": "x"]
        XCTAssertTrue(SettingReader.bool(s, "b1", default: false))
        XCTAssertFalse(SettingReader.bool(s, "b2", default: true))
        XCTAssertTrue(SettingReader.bool(s, "bad", default: true))
        XCTAssertEqual(SettingReader.double(s, "n"), 3.6)
        XCTAssertEqual(SettingReader.double(s, "ns"), 2.5)
        XCTAssertNil(SettingReader.double(s, "bad"))
        XCTAssertEqual(SettingReader.string(s, "s"), "7")
        XCTAssertEqual(SettingReader.string(s, "missing", default: "d"), "d")
        XCTAssertEqual(SettingReader.int(s, "n", default: 1, range: 1...3), 3, "rounded, then clamped")
        XCTAssertEqual(SettingReader.int(s, "bad", default: 2, range: 1...3), 2)
    }

    func testAge() {
        let now = Date()
        XCTAssertEqual(Age.text(since: now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(Age.text(since: now.addingTimeInterval(-12 * 60), now: now), "12 min ago")
        XCTAssertEqual(Age.text(since: now.addingTimeInterval(-3 * 3600 - 5), now: now), "3 h ago")
        XCTAssertEqual(Age.text(since: now.addingTimeInterval(-2 * 86_400), now: now), "2 d ago")
    }
}
