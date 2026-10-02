import Foundation
import XCTest
@testable import widgetHUDKit

final class WidgetOptionsTests: XCTestCase {
    func testClockDefaults() {
        let o = ClockOptions(settings: [:])
        XCTAssertTrue(o.isLocal)
        XCTAssertEqual(o.style, .auto)
        XCTAssertEqual(o.timeFormat, "app")
        XCTAssertFalse(o.seconds)
        XCTAssertTrue(o.isAnalog(small: true))
        XCTAssertFalse(o.isAnalog(small: false))
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        XCTAssertEqual(o.zone(current: oslo), oslo)
        XCTAssertEqual(o.displayLabel(zone: oslo, current: oslo), "Oslo")
    }

    func testClockZoneResolution() {
        XCTAssertEqual(ClockOptions.resolveZone("Europe/Oslo")?.identifier, "Europe/Oslo")
        XCTAssertEqual(ClockOptions.resolveZone("oslo")?.identifier, "Europe/Oslo")
        XCTAssertEqual(ClockOptions.resolveZone("new york")?.identifier, "America/New_York")
        XCTAssertEqual(ClockOptions.resolveZone("america/new york")?.identifier, "America/New_York")
        XCTAssertNotNil(ClockOptions.resolveZone("utc"))
        XCTAssertNil(ClockOptions.resolveZone("Atlantis"))
        XCTAssertNil(ClockOptions(settings: ["timeZone": "Atlantis"]).zone())
    }

    func testClockLabels() {
        let tokyo = ClockOptions(settings: ["timeZone": "Tokyo", "style": "digital", "seconds": "on", "timeFormat": "24h"])
        let zone = tokyo.zone()
        XCTAssertEqual(zone?.identifier, "Asia/Tokyo")
        XCTAssertEqual(tokyo.displayLabel(zone: zone), "Tokyo")
        XCTAssertFalse(tokyo.isAnalog(small: true))
        XCTAssertTrue(tokyo.seconds)
        XCTAssertEqual(ClockOptions(settings: ["timeZone": "Tokyo", "label": "Office"]).displayLabel(zone: zone), "Office")
        XCTAssertEqual(ClockOptions(settings: ["timeZone": "Atlantis"]).displayLabel(zone: nil), "Atlantis")
        XCTAssertEqual(ClockOptions.city(of: TimeZone(identifier: "America/Argentina/Buenos_Aires")!), "Buenos Aires")
        let date = Date(timeIntervalSince1970: 1_790_904_600)  // 2026-10-01, both on summer time
        XCTAssertEqual(ClockOptions.offsetLabel(TimeZone(identifier: "Europe/Oslo")!, from: TimeZone(identifier: "America/New_York")!, at: date), "+6h")
        XCTAssertEqual(ClockOptions.offsetLabel(TimeZone(identifier: "Asia/Kolkata")!, from: TimeZone(identifier: "UTC")!, at: date), "+5h30")
        XCTAssertEqual(ClockOptions.offsetLabel(TimeZone(identifier: "America/Chicago")!, from: TimeZone(identifier: "America/New_York")!, at: date), "-1h")
        XCTAssertNil(ClockOptions.offsetLabel(TimeZone(identifier: "UTC")!, from: TimeZone(identifier: "GMT")!, at: date))
    }

    func testWeatherNeedsALookupUntilCoordinatesMatchThePlace() {
        XCTAssertFalse(WeatherOptions(settings: [:]).needsLookup, "no place: nothing to look up")
        XCTAssertNil(WeatherOptions(settings: [:]).point)
        let fresh = WeatherOptions(settings: ["place": "Oslo"])
        XCTAssertTrue(fresh.needsLookup)
        XCTAssertNil(fresh.point)
        let found = GeoPlace(name: "Oslo", admin1: "Oslo", country: "Norway", latitude: 59.91, longitude: 10.75)
        var settings: [String: Any] = ["place": "Oslo"]
        settings.merge(WeatherOptions.resolution(for: "Oslo", found: found)) { $1 }
        let resolved = WeatherOptions(settings: settings)
        XCTAssertFalse(resolved.needsLookup)
        XCTAssertEqual(resolved.point, GeoPoint(latitude: 59.91, longitude: 10.75))
        XCTAssertEqual(resolved.displayName, "Oslo")
        settings["place"] = "  oslo "
        XCTAssertFalse(WeatherOptions(settings: settings).needsLookup, "case and spacing do not matter")
        settings["place"] = "Bergen"
        XCTAssertTrue(WeatherOptions(settings: settings).needsLookup, "a new place is looked up again")
        XCTAssertEqual(WeatherOptions(settings: settings).displayName, "Oslo", "until then the found name shows")
        XCTAssertTrue(WeatherOptions(settings: ["place": "Oslo", "latitude": 200, "longitude": 0, "resolvedPlace": "Oslo"]).needsLookup)
    }

    func testWeatherDefaults() {
        let o = WeatherOptions(settings: [:])
        XCTAssertEqual(o.units, "app")
        XCTAssertTrue(o.showHourly)
        XCTAssertTrue(o.showDaily)
        XCTAssertFalse(WeatherOptions(settings: ["showDaily": false]).showDaily)
    }

    func testCalendarOptions() {
        let o = CalendarOptions(settings: [:])
        XCTAssertEqual(o.calendars, [])
        XCTAssertEqual(o.daysAhead, 3)
        let work = CalendarEvent(id: "1", title: "a", start: Date(), end: Date(), calendar: "Work")
        XCTAssertTrue(o.includes(work))
        let picked = CalendarOptions(settings: ["calendars": " work, Family ,", "daysAhead": 40])
        XCTAssertEqual(picked.calendars, ["work", "Family"])
        XCTAssertEqual(picked.daysAhead, 14, "clamped")
        XCTAssertTrue(picked.includes(work))
        var home = work
        home.calendar = "Home"
        XCTAssertFalse(picked.includes(home))
    }
}
