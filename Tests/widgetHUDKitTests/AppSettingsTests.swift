import Foundation
import XCTest
@testable import widgetHUDKit

final class AppSettingsTests: XCTestCase {
    func testDefaultsFollowTheRegion() {
        XCTAssertEqual(AppSettings(), AppSettings(temperatureUnit: .auto, timeFormat: .auto))
    }

    func testApplyingParsesStrings() throws {
        let next = try AppSettings().applying(["temperatureUnit": "celsius", "timeFormat": "24h"])
        XCTAssertEqual(next, AppSettings(temperatureUnit: .celsius, timeFormat: .twentyFour))
    }

    func testApplyingRejectsBadValuesWithoutPartialChanges() {
        let settings = AppSettings()
        XCTAssertThrowsError(try settings.applying(["temperatureUnit": "kelvin"])) {
            XCTAssertEqual($0 as? AppSettings.SettingsError, .invalid(key: "temperatureUnit", value: "kelvin"))
        }
        XCTAssertThrowsError(try settings.applying(["timeFormat": "24h", "temperatureUnit": "kelvin"]))
        XCTAssertThrowsError(try settings.applying(["colour": "red"])) {
            XCTAssertEqual($0 as? AppSettings.SettingsError, .unknownKey("colour"))
        }
    }

    func testSaveAndLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("preferences.json")
        XCTAssertEqual(AppSettings.load(from: url), AppSettings(), "missing file reads as defaults")
        let custom = AppSettings(temperatureUnit: .fahrenheit, timeFormat: .twelve)
        try custom.save(to: url)
        XCTAssertEqual(AppSettings.load(from: url), custom)
    }

    func testLoadMergesSavedValuesOverDefaultsKeyByKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"temperatureUnit": "celsius", "retired": 3}"#.utf8).write(to: url)
        XCTAssertEqual(AppSettings.load(from: url), AppSettings(temperatureUnit: .celsius))
        try Data(#"{"temperatureUnit": "kelvin", "timeFormat": "12h"}"#.utf8).write(to: url)
        XCTAssertEqual(AppSettings.load(from: url), AppSettings(timeFormat: .twelve))
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(AppSettings.load(from: url), AppSettings())
    }

    func testJSONCoversEveryKey() {
        XCTAssertEqual(Set(AppSettings().json.keys), AppSettings.keys)
    }
}
