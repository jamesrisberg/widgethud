import Foundation
import HUDKit
import XCTest
@testable import widgetHUD
import widgetHUDKit

/// Counts requests and answers from a script, so the store's rules can be checked without a
/// network.
private final class FakeFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var _forecasts = 0, _lookups = 0
    var fail: Error?
    var failLookups: Error?
    /// What the geocoding API answers.
    var places = #"{"results":[{"name":"Oslo","latitude":59.91,"longitude":10.75,"country":"Norway"}]}"#
    var forecasts: Int { lock.withLock { _forecasts } }
    var lookups: Int { lock.withLock { _lookups } }

    lazy var client = WeatherClient { [unowned self] url in
        if url.host == "geocoding-api.open-meteo.com" {
            self.lock.withLock { self._lookups += 1 }
            if let fail = self.failLookups { throw fail }
            return Data(self.places.utf8)
        }
        self.lock.withLock { self._forecasts += 1 }
        if let fail = self.fail { throw fail }
        return Data(osloForecast.utf8)
    }
}

/// An Open-Meteo forecast for Oslo (the Kit tests have the full one).
private let osloForecast = """
{"timezone":"Europe/Oslo","current":{"temperature_2m":15.7,"weather_code":3,"is_day":0},
 "hourly":{"time":[1790902800],"temperature_2m":[15.8],"weather_code":[3],"is_day":[0]},
 "daily":{"time":[1790892000],"weather_code":[63],"temperature_2m_max":[16.3],"temperature_2m_min":[14.0]}}
"""

@MainActor
final class WeatherStoreTests: XCTestCase {
    private let oslo = GeoPoint(latitude: 59.91, longitude: 10.75)
    private let resolved: [String: Any] = ["place": "Oslo", "latitude": 59.91, "longitude": 10.75, "resolvedPlace": "Oslo",
                                           "resolvedName": "Oslo, Norway"]

    private func settle(_ store: WeatherStore) async {
        for _ in 0..<200 where store.entries.values.contains(where: \.loading) || store.lookups.values.contains(.looking) {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func tempCache() -> (WeatherCache, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (WeatherCache(url: dir.appendingPathComponent("weather-cache.json")), dir)
    }

    func testForecastsAreSharedCachedAndRefreshedWhenDue() async throws {
        let (cache, dir) = tempCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeFetch()
        var now = Date(timeIntervalSince1970: 1_790_904_700)
        let store = WeatherStore(client: fake.client, cache: cache)
        store.now = { now }
        store.show("a", options: WeatherOptions(settings: resolved)) { _ in XCTFail("has coordinates") }
        store.show("b", options: WeatherOptions(settings: resolved)) { _ in XCTFail("has coordinates") }
        await settle(store)
        XCTAssertEqual(fake.forecasts, 1, "same place: one request")
        XCTAssertEqual(fake.lookups, 0)
        XCTAssertEqual(store.entry(for: oslo).report?.current.temperature, 15.7)
        XCTAssertNotNil(cache.load().reports[oslo.key], "saved for the next launch")
        XCTAssertNotNil(cache.load().places["oslo"], "the settings' coordinates serve other widgets with this text")

        now += 10 * 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.forecasts, 1, "fresh for 15 minutes")
        now += 6 * 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.forecasts, 2)

        let relaunched = WeatherStore(client: fake.client, cache: cache)
        XCTAssertNotNil(relaunched.entry(for: oslo).report, "the cache shows at launch")
    }

    func testAPlaceIsLookedUpOnceAndWrittenBackToEachInstanceOnce() async {
        let fake = FakeFetch()
        let store = WeatherStore(client: fake.client, cache: nil)
        var writes: [String: [[String: Any]]] = [:]
        func show(_ id: String, _ place: String) {
            store.show(id, options: WeatherOptions(settings: ["place": place])) { writes[id, default: []].append($0) }
        }
        show("a", "Oslo")
        show("b", " oslo ")
        XCTAssertEqual(store.lookup(for: WeatherOptions(settings: ["place": "Oslo"])), .looking)
        await settle(store)
        XCTAssertEqual(fake.lookups, 1, "one lookup per place text")
        XCTAssertEqual(writes["a"]?.count, 1)
        XCTAssertEqual(writes["b"]?.count, 1)
        XCTAssertEqual(writes["a"]?.first?["latitude"] as? Double, 59.91)
        XCTAssertEqual(writes["a"]?.first?["resolvedPlace"] as? String, "Oslo")
        XCTAssertEqual(writes["b"]?.first?["resolvedPlace"] as? String, "oslo", "each with the text it typed")
        XCTAssertEqual(store.point(for: WeatherOptions(settings: ["place": "OSLO"])), oslo)
        // A third widget later: served from memory, written back once.
        show("c", "Oslo")
        XCTAssertEqual(fake.lookups, 1)
        XCTAssertEqual(writes["c"]?.count, 1)
        XCTAssertEqual(store.tracked["c"], oslo)
    }

    func testCoordinatesThatComeBackMissingDoNotLoop() async {
        let fake = FakeFetch()
        let store = WeatherStore(client: fake.client, cache: nil)
        var writes = 0
        let bare = WeatherOptions(settings: ["place": "Oslo"])
        store.show("a", options: bare) { _ in writes += 1 }
        await settle(store)
        XCTAssertEqual(writes, 1)
        // The host dropped the keys its schema does not list and sent the settings back.
        for _ in 0..<3 { store.show("a", options: bare) { _ in writes += 1 } }
        await settle(store)
        XCTAssertEqual(writes, 1, "never written again for the same text")
        XCTAssertEqual(fake.lookups, 1, "never looked up again")
        XCTAssertEqual(store.tracked["a"], oslo, "still shows the weather")
        // A new place is a new lookup and one more write.
        fake.places = #"{"results":[{"name":"Bergen","latitude":60.39,"longitude":5.32,"country":"Norway"}]}"#
        store.show("a", options: WeatherOptions(settings: ["place": "Bergen"])) { _ in writes += 1 }
        await settle(store)
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(fake.lookups, 2)
    }

    func testNoMatchOrInvalidCoordinatesEndTheLookup() async {
        let fake = FakeFetch()
        let store = WeatherStore(client: fake.client, cache: nil)
        fake.places = #"{"results":[{"name":"Nowhere","latitude":120,"longitude":10,"country":"X"}]}"#
        let options = WeatherOptions(settings: ["place": "Nowhere"])
        store.show("a", options: options) { _ in XCTFail("nothing to write") }
        await settle(store)
        XCTAssertEqual(store.lookup(for: options), .notFound, "invalid coordinates: not found, not Finding… forever")
        XCTAssertNil(store.point(for: options))
        fake.places = #"{"generationtime_ms":0.2}"#
        let none = WeatherOptions(settings: ["place": "Atlantis"])
        store.show("b", options: none) { _ in XCTFail("nothing to write") }
        await settle(store)
        XCTAssertEqual(store.lookup(for: none), .notFound)
    }

    func testFailedLookupsBackOff() async {
        let fake = FakeFetch()
        fake.failLookups = URLError(.notConnectedToInternet)
        var now = Date(timeIntervalSince1970: 1_790_904_700)
        let store = WeatherStore(client: fake.client, cache: nil)
        store.now = { now }
        let options = WeatherOptions(settings: ["place": "Oslo"])
        var writes = 0
        store.show("a", options: options) { _ in writes += 1 }
        await settle(store)
        XCTAssertEqual(store.lookup(for: options), .failed("Offline", retryAt: now + 60))
        now += 30
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.lookups, 1, "not before the back-off")
        now += 30
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.lookups, 2)
        XCTAssertEqual(store.lookup(for: options), .failed("Offline", retryAt: now + 120), "doubled")
        fake.failLookups = nil
        now += 120
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.lookups, 3)
        XCTAssertNil(store.lookup(for: options))
        XCTAssertEqual(writes, 1)
    }

    func testForecastFailureKeepsTheLastReportAndRetriesAfterAWhile() async {
        let fake = FakeFetch()
        var now = Date(timeIntervalSince1970: 1_790_904_700)
        let store = WeatherStore(client: fake.client, cache: nil)
        store.now = { now }
        store.show("a", options: WeatherOptions(settings: resolved)) { _ in }
        await settle(store)
        fake.fail = URLError(.notConnectedToInternet)
        now += 16 * 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(store.entry(for: oslo).error, "Offline")
        XCTAssertNotNil(store.entry(for: oslo).report, "the last report stays")
        let count = fake.forecasts
        now += 60
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.forecasts, count, "no retry within two minutes")
        now += 2 * 60
        fake.fail = nil
        store.refreshDue()
        await settle(store)
        XCTAssertEqual(fake.forecasts, count + 1)
        XCTAssertNil(store.entry(for: oslo).error)
    }

    func testWidgetsThatGoTakeTheirForecastsAndPlacesOutOfTheCache() async {
        let (cache, dir) = tempCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeFetch()
        let store = WeatherStore(client: fake.client, cache: cache)
        var live: Set<String> = ["a", "b"]
        store.liveInstances = { live }
        store.show("a", options: WeatherOptions(settings: resolved)) { _ in }
        store.show("b", options: WeatherOptions(settings: resolved)) { _ in }
        await settle(store)
        store.untrack("a")
        XCTAssertNotNil(cache.load().reports[oslo.key], "b still shows it")
        live = []
        store.refreshDue()
        XCTAssertTrue(store.tracked.isEmpty)
        XCTAssertEqual(cache.load(), WeatherCache.Contents(), "nothing shown, nothing kept")
    }

    func testSampleStoreNeedsNoNetwork() {
        let store = WeatherStore.sample()
        XCTAssertTrue(store.isSample)
        XCTAssertNotNil(store.entry(for: oslo).report)
    }
}

private final class FakeCalendars: CalendarProviding, @unchecked Sendable {
    private let lock = NSLock()
    var onChange: (() -> Void)?
    var access: CalendarAccess
    var grant: CalendarAccess
    var requests = 0
    var events: [CalendarEvent] = []
    private var _loads = 0
    var loads: Int { lock.withLock { _loads } }

    init(access: CalendarAccess, grant: CalendarAccess = .granted) {
        self.access = access
        self.grant = grant
    }

    func requestAccess() async -> CalendarAccess {
        requests += 1
        access = grant
        return access
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        lock.withLock { _loads += 1 }
        Thread.sleep(forTimeInterval: 0.02)
        return events
    }
}

@MainActor
final class CalendarStoreTests: XCTestCase {
    private func settle(_ until: () -> Bool) async {
        for _ in 0..<200 where !until() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    private func event(_ id: String) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: Date(), end: Date().addingTimeInterval(60), calendar: "Work")
    }

    func testFirstWidgetAsksForAccessThenLoads() async {
        let fake = FakeCalendars(access: .notDetermined)
        fake.events = [event("1")]
        let store = CalendarStore(provider: fake)
        XCTAssertEqual(store.access, .notDetermined)
        XCTAssertFalse(store.isActive, "nothing happens before a calendar widget shows")
        store.appeared("a")
        store.appeared("b")
        await settle { store.events.count == 1 }
        XCTAssertEqual(fake.requests, 1, "asked once")
        XCTAssertEqual(store.access, .granted)
        XCTAssertTrue(store.isActive)
    }

    func testRefusedAccessShowsNoEventsAndDoesNotAskAgain() async {
        let fake = FakeCalendars(access: .notDetermined, grant: .denied)
        fake.events = [event("1")]
        let store = CalendarStore(provider: fake)
        store.appeared("a")
        await settle { store.access == .denied }
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(fake.requests, 1)
    }

    func testAGrantInSystemSettingsShowsOnTheNextTick() async {
        let fake = FakeCalendars(access: .denied)
        fake.events = [event("1")]
        let store = CalendarStore(provider: fake)
        store.appeared("a")
        XCTAssertEqual(store.access, .denied)
        fake.access = .granted  // the user flipped the switch; EventKit says nothing
        store.tick()
        await settle { store.events.count == 1 }
        XCTAssertEqual(store.access, .granted)
        XCTAssertEqual(store.events.count, 1)
    }

    func testTheLastWidgetGoingStopsTheStore() async {
        let store = CalendarStore(provider: FakeCalendars(access: .granted))
        var live: Set<String> = ["a", "b"]
        store.liveInstances = { live }
        store.appeared("a")
        store.appeared("b")
        store.disappeared("a")
        XCTAssertTrue(store.isActive)
        live = []  // b's window closed without an onDisappear
        store.tick()
        XCTAssertFalse(store.isActive)
        XCTAssertEqual(store.shown, [])
        store.appeared("c")
        XCTAssertTrue(store.isActive, "a new widget starts it again")
        store.disappeared("c")
        XCTAssertFalse(store.isActive)
    }

    func testABurstOfChangesLoadsOnceAndKeepsTheNewest() async {
        let fake = FakeCalendars(access: .granted)
        let store = CalendarStore(provider: fake)
        store.appeared("a")
        await settle { store.loadedAt != nil }
        let before = fake.loads
        fake.events = [event("2")]
        for _ in 0..<10 { store.reload() }
        await settle { store.events.map(\.id) == ["2"] }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.events.map(\.id), ["2"])
        XCTAssertLessThanOrEqual(fake.loads - before, 2, "queued reloads behind a newer one are skipped")
    }

    func testChangesReload() async {
        let fake = FakeCalendars(access: .granted)
        let store = CalendarStore(provider: fake)
        store.appeared("a")
        await settle { store.loadedAt != nil }
        fake.events = [event("2")]
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
