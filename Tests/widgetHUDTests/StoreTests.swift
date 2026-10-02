import Foundation
import HUDKit
import XCTest
@testable import widgetHUD
import widgetHUDKit

/// Counts requests and answers from a script, so the store's refresh rules can be checked
/// without a network.
private final class FakeFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var fail: Error?
    var count: Int { lock.withLock { _count } }

    lazy var client = WeatherClient { [unowned self] _ in
        self.lock.withLock { self._count += 1 }
        if let fail = self.fail { throw fail }
        return Data(WeatherTests_oslo.utf8)
    }
}

/// The Kit tests' Oslo answer, shared through a constant (test targets cannot import each other).
private let WeatherTests_oslo = """
{"timezone":"Europe/Oslo","current":{"temperature_2m":15.7,"weather_code":3,"is_day":0},
 "hourly":{"time":[1790902800],"temperature_2m":[15.8],"weather_code":[3],"is_day":[0]},
 "daily":{"time":[1790892000],"weather_code":[63],"temperature_2m_max":[16.3],"temperature_2m_min":[14.0]}}
"""

@MainActor
final class WeatherStoreTests: XCTestCase {
    private let oslo = GeoPoint(latitude: 59.91, longitude: 10.75)

    private func settle(_ store: WeatherStore) async {
        for _ in 0..<200 where store.entries.values.contains(where: \.loading) { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testTrackFetchesOnceCachesAndRefreshesWhenDue() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeFetch()
        var now = Date(timeIntervalSince1970: 1_790_904_700)
        let cache = WeatherCache(url: dir.appendingPathComponent("weather-cache.json"))
        let store = WeatherStore(client: fake.client, cache: cache)
        store.now = { now }
        store.track("a", at: oslo)
        store.track("b", at: oslo)   // same place: shares the request
        await settle(store)
        XCTAssertEqual(fake.count, 1)
        XCTAssertEqual(store.entry(for: oslo).report?.current.temperature, 15.7)
        XCTAssertNotNil(cache.load()[oslo.key], "saved for the next launch")

        now += 10 * 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.count, 1, "fresh for 15 minutes")
        now += 6 * 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.count, 2)

        let relaunched = WeatherStore(client: fake.client, cache: cache)
        XCTAssertNotNil(relaunched.entry(for: oslo).report, "the cache shows at launch")
    }

    func testFailureKeepsTheLastReportAndRetriesAfterAWhile() async {
        let fake = FakeFetch()
        var now = Date(timeIntervalSince1970: 1_790_904_700)
        let store = WeatherStore(client: fake.client, cache: nil)
        store.now = { now }
        store.track("a", at: oslo)
        await settle(store)
        fake.fail = URLError(.notConnectedToInternet)
        now += 16 * 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(store.entry(for: oslo).error, "Offline")
        XCTAssertNotNil(store.entry(for: oslo).report, "the last report stays")
        let count = fake.count
        now += 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.count, count, "no retry within two minutes")
        now += 2 * 60
        fake.fail = nil
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.count, count + 1)
        XCTAssertNil(store.entry(for: oslo).error)
    }

    func testPlacesNoWidgetShowsAreForgotten() async {
        let fake = FakeFetch()
        let store = WeatherStore(client: fake.client, cache: nil)
        var live: Set<String> = ["a"]
        store.liveInstances = { live }
        store.track("a", at: oslo)
        await settle(store)
        live = []
        store.refreshDue(force: true)
        XCTAssertTrue(store.tracked.isEmpty)
    }

    func testSampleStoreNeedsNoNetwork() {
        let store = WeatherStore.sample()
        XCTAssertTrue(store.isSample)
        XCTAssertNotNil(store.entry(for: oslo).report)
    }
}

private final class FakeCalendars: CalendarProviding, @unchecked Sendable {
    var onChange: (() -> Void)?
    var access: CalendarAccess
    var grant: CalendarAccess
    var requests = 0
    var events: [CalendarEvent] = []

    init(access: CalendarAccess, grant: CalendarAccess = .granted) {
        self.access = access
        self.grant = grant
    }

    func requestAccess() async -> CalendarAccess {
        requests += 1
        access = grant
        return access
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] { events }
}

@MainActor
final class CalendarStoreTests: XCTestCase {
    private func settle(_ until: () -> Bool) async {
        for _ in 0..<200 where !until() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testFirstWidgetAsksForAccessThenLoads() async {
        let fake = FakeCalendars(access: .notDetermined)
        fake.events = [CalendarEvent(id: "1", title: "a", start: Date(), end: Date().addingTimeInterval(60), calendar: "Work")]
        let store = CalendarStore(provider: fake)
        XCTAssertEqual(store.access, .notDetermined)
        store.activate()
        store.activate()
        await settle { store.events.count == 1 }
        XCTAssertEqual(fake.requests, 1, "asked once")
        XCTAssertEqual(store.access, .granted)
        XCTAssertEqual(store.events.count, 1)
    }

    func testRefusedAccessShowsNoEventsAndDoesNotAskAgain() async {
        let fake = FakeCalendars(access: .notDetermined, grant: .denied)
        fake.events = [CalendarEvent(id: "1", title: "a", start: Date(), end: Date(), calendar: "Work")]
        let store = CalendarStore(provider: fake)
        store.activate()
        await settle { store.access == .denied }
        XCTAssertEqual(store.access, .denied)
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(fake.requests, 1)
    }

    func testChangesReload() async {
        let fake = FakeCalendars(access: .granted)
        let store = CalendarStore(provider: fake)
        store.activate()
        await settle { store.loadedAt != nil }
        fake.events = [CalendarEvent(id: "2", title: "b", start: Date(), end: Date().addingTimeInterval(60), calendar: "Home")]
        fake.onChange?()
        await settle { store.events.count == 1 }
        XCTAssertEqual(store.events.map(\.id), ["2"])
    }
}

@MainActor
final class SnapshotTests: XCTestCase {
    func testEveryTypeAtEverySizeRendersAndTheSheetCollectsThem() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sheet = dir.appendingPathComponent("w.png")
        let written = try Snapshot.run(arguments: ["widgetHUD", "--snapshot", sheet.path])
        XCTAssertEqual(written.count, Snapshot.all.count + 1)
        XCTAssertEqual(written.last, sheet)
        for url in written {
            let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)), url.lastPathComponent)
            XCTAssertGreaterThan(rep.pixelsWide, 300, url.lastPathComponent)
        }
        let one = dir.appendingPathComponent("one.png")
        XCTAssertEqual(try Snapshot.run(arguments: ["x", "--snapshot", one.path, "--type", "weather", "--size", "large"]), [one])
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: one)))
        XCTAssertEqual(rep.pixelsWide, Int(HUDWidgetSize.large.points().width * 2))
        XCTAssertThrowsError(try Snapshot.run(arguments: ["x", "--snapshot", one.path, "--type", "clock", "--size", "large"]))
    }
}
