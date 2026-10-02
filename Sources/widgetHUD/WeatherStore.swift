import AppKit
import widgetHUDKit

/// Forecasts and place lookups for every weather widget.
///
/// - Places: a widget's place text is looked up once per text (`WeatherOptions.placeKey`, so
///   "Oslo" and " oslo" are one lookup however many widgets show it), remembered in memory and on
///   disk, and the coordinates are written back to each instance's settings once. An instance
///   whose settings come back without them (a host that drops keys its schema does not list) is
///   served from the remembered place, never written to again for the same text, so nothing
///   loops. Failed lookups back off (`Backoff`), a minute doubling to 30.
/// - Forecasts: shared by instances at the same place (`GeoPoint.key`), refreshed every 15
///   minutes while a widget shows them, retried 2 minutes after a failure, and kept on disk
///   (`WeatherCache`) so widgets have something at launch and offline. Forecasts and places no
///   widget shows any more are dropped from the cache when their last widget goes.
@MainActor
final class WeatherStore: ObservableObject {
    struct Entry: Equatable {
        var report: WeatherReport?
        /// Why the last fetch failed; nil after a success.
        var error: String?
        var loading = false
        var lastAttempt: Date?
    }

    /// A place being looked up, or one that could not be.
    enum Lookup: Equatable {
        case looking
        case notFound
        /// The reason, and when the next attempt is due.
        case failed(String, retryAt: Date)
    }

    static let refreshInterval: TimeInterval = 15 * 60
    static let retryInterval: TimeInterval = 2 * 60
    /// A report older than this is shown with its age.
    static let staleAfter: TimeInterval = 45 * 60

    @Published private(set) var entries: [String: Entry] = [:]
    /// Place key → what the text was found to be.
    @Published private(set) var places: [String: GeoPlace] = [:]
    /// Place key → a lookup in flight or that failed.
    @Published private(set) var lookups: [String: Lookup] = [:]
    /// Instance id → the forecast point it shows.
    private(set) var tracked: [String: GeoPoint] = [:]

    /// An instance shown by `show`: its place and how to write coordinates back to it.
    private struct Shown {
        var key: String
        var text: String
        var writeBack: ([String: Any]) -> Void
    }
    private var shown: [String: Shown] = [:]
    /// Instance id → the place key whose coordinates were written to it.
    private var wroteBack: [String: String] = [:]
    private var failures: [String: Int] = [:]

    /// nil: sample data (no network).
    let client: WeatherClient?
    let cache: WeatherCache?
    var now: () -> Date = Date.init
    /// The instances still placed: instances gone from it are untracked on the next check.
    var liveInstances: (() -> Set<String>)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(client: WeatherClient?, cache: WeatherCache?) {
        self.client = client
        self.cache = cache
        let contents = cache?.load() ?? WeatherCache.Contents()
        for (key, report) in contents.reports { entries[key] = Entry(report: report) }
        places = contents.places.filter { $0.value.point.isValid }
    }

    static func sample() -> WeatherStore { WeatherStore(client: nil, cache: nil) }

    var isSample: Bool { client == nil }

    /// Starts the periodic check (once a minute, and on wake): due forecasts, due lookup retries,
    /// instances that are gone.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDue() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDue() }
        }
    }

    // MARK: - Instances

    /// Instance `id` shows `options` (call on appear and on every settings change). Tracks its
    /// forecast, looking the place up first when needed; `writeBack` receives the settings to add
    /// (`WeatherOptions.resolution`) once per instance and place.
    func show(_ id: String, options: WeatherOptions, writeBack: @escaping ([String: Any]) -> Void) {
        guard !options.place.isEmpty else {
            untrack(id)
            return
        }
        let key = options.placeKey
        shown[id] = Shown(key: key, text: options.place, writeBack: writeBack)
        if let point = options.point {
            // The settings carry the coordinates: remember them for other widgets with this text.
            if places[key] == nil {
                places[key] = GeoPlace(name: options.resolvedName.isEmpty ? options.place : options.resolvedName,
                                       latitude: point.latitude, longitude: point.longitude)
                saveCache()
            }
            wroteBack[id] = key
            track(id, at: point)
        } else if let found = places[key] {
            track(id, at: found.point)
            deliver(found, to: id)
        } else {
            track(id, at: nil)
            lookUpIfDue(key)
        }
    }

    /// The point a widget with `options` shows: its own coordinates, else its place's.
    func point(for options: WeatherOptions) -> GeoPoint? {
        guard !options.place.isEmpty else { return nil }
        return options.point ?? places[options.placeKey]?.point
    }

    /// The lookup state of a widget's place (nil once found, or before anything happened).
    func lookup(for options: WeatherOptions) -> Lookup? { lookups[options.placeKey] }

    /// Instance `id` is gone: forget it, and drop forecasts and places no widget shows.
    func untrack(_ id: String) {
        let had = tracked[id] != nil || shown[id] != nil
        tracked[id] = nil
        shown[id] = nil
        wroteBack[id] = nil
        if had { prune() }
    }

    private func track(_ id: String, at point: GeoPoint?) {
        let old = tracked[id]
        tracked[id] = point
        if let point { refreshIfDue(point) }
        if old != nil, old != point { prune() }
    }

    private func deliver(_ found: GeoPlace, to id: String) {
        guard let s = shown[id], wroteBack[id] != s.key else { return }
        wroteBack[id] = s.key
        s.writeBack(WeatherOptions.resolution(for: s.text, found: found))
    }

    private func prune() {
        let points = Set(tracked.values.map(\.key))
        let keys = Set(shown.values.map(\.key))
        let reports = entries.filter { points.contains($0.key) || $0.value.loading }
        let known = places.filter { keys.contains($0.key) }
        guard reports.count != entries.count || known.count != places.count else { return }
        entries = reports
        places = known
        lookups = lookups.filter { keys.contains($0.key) }
        saveCache()
    }

    // MARK: - Lookups

    private func lookUpIfDue(_ key: String) {
        switch lookups[key] {
        case .looking, .notFound: return
        case .failed(_, let retryAt) where now() < retryAt: return
        default: break
        }
        guard let text = shown.values.first(where: { $0.key == key })?.text else { return }
        lookups[key] = .looking
        Task { [weak self] in
            let result: Result<GeoPlace?, Error>
            do { result = .success(try await self?.lookUp(text)) } catch { result = .failure(error) }
            self?.finishLookup(key, result)
        }
    }

    private func finishLookup(_ key: String, _ result: Result<GeoPlace?, Error>) {
        switch result {
        case .success(let found?) where found.point.isValid:
            failures[key] = nil
            lookups[key] = nil
            places[key] = found
            saveCache()
            for (id, s) in shown where s.key == key {
                track(id, at: found.point)
                deliver(found, to: id)
            }
        case .success:
            // Nothing by that name, or nowhere valid: the widget says so until the place changes.
            failures[key] = nil
            lookups[key] = .notFound
        case .failure(let error):
            let attempts = (failures[key] ?? 0) + 1
            failures[key] = attempts
            lookups[key] = .failed(Self.describe(error), retryAt: now().addingTimeInterval(Backoff.delay(attempts: attempts)))
        }
    }

    /// Looks a place up (sample data: always found).
    func lookUp(_ text: String) async throws -> GeoPlace? {
        guard let client else { return SampleData.lookUp(text) }
        return try await client.lookUp(text)
    }

    func search(_ text: String) async throws -> [GeoPlace] {
        guard let client else { return SampleData.lookUp(text).map { [$0] } ?? [] }
        return try await client.search(GeoPlace.query(text).name)
    }

    // MARK: - Forecasts

    func entry(for point: GeoPoint) -> Entry {
        if isSample { return Entry(report: SampleData.weather(now: now())) }
        return entries[point.key] ?? Entry()
    }

    /// Drops instances that are gone, retries due lookups and fetches every tracked place whose
    /// report is due (or every one with `force`).
    func refreshDue(force: Bool = false) {
        if let live = liveInstances?() {
            for id in Set(tracked.keys).union(shown.keys) where !live.contains(id) { untrack(id) }
        }
        for key in Set(shown.values.map(\.key)) where places[key] == nil { lookUpIfDue(key) }
        for point in Set(tracked.values) { refreshIfDue(point, force: force) }
    }

    private func refreshIfDue(_ point: GeoPoint, force: Bool = false) {
        guard let client else { return }
        let entry = entries[point.key] ?? Entry()
        guard !entry.loading else { return }
        let t = now()
        if !force {
            if let report = entry.report, !report.isOlder(than: Self.refreshInterval, now: t) { return }
            if entry.error != nil, let last = entry.lastAttempt, t.timeIntervalSince(last) < Self.retryInterval { return }
        }
        var next = entry
        next.loading = true
        next.lastAttempt = t
        entries[point.key] = next
        Task { [weak self] in
            let result: Result<WeatherReport, Error>
            do { result = .success(try await client.forecast(point, now: t)) } catch { result = .failure(error) }
            self?.finish(point, result)
        }
    }

    private func finish(_ point: GeoPoint, _ result: Result<WeatherReport, Error>) {
        var entry = entries[point.key] ?? Entry()
        entry.loading = false
        switch result {
        case .success(let report):
            entry.report = report
            entry.error = nil
        case .failure(let error):
            entry.error = Self.describe(error)
        }
        entries[point.key] = entry
        if case .success = result { saveCache() }
        if !tracked.values.contains(point) { prune() }
    }

    private func saveCache() {
        guard let cache else { return }
        do {
            try cache.save(WeatherCache.Contents(reports: entries.compactMapValues(\.report), places: places))
        } catch {
            NSLog("widgetHUD: weather cache not saved: %@", "\(error)")
        }
    }

    /// Short words for a failure: "Offline" for the usual network errors.
    static func describe(_ error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff:
                return "Offline"
            default:
                return url.localizedDescription
            }
        }
        return "\(error)"
    }

    var json: [String: Any] {
        [
            "sample": isSample,
            "places": entries.keys.sorted().map { key -> [String: Any] in
                let e = entries[key]!
                var d: [String: Any] = ["place": key, "loading": e.loading]
                if let r = e.report { d["fetchedAt"] = ISO8601DateFormatter().string(from: r.fetchedAt) }
                if let error = e.error { d["error"] = error }
                return d
            },
            "lookups": places.keys.sorted().map { key -> [String: Any] in ["text": key, "found": places[key]!.displayName] }
                + lookups.keys.sorted().map { key -> [String: Any] in
                    switch lookups[key]! {
                    case .looking: return ["text": key, "state": "looking"]
                    case .notFound: return ["text": key, "state": "notFound"]
                    case .failed(let why, let at): return ["text": key, "state": "failed", "error": why,
                                                           "retryAt": ISO8601DateFormatter().string(from: at)]
                    }
                },
            "instances": Set(tracked.keys).union(shown.keys).sorted(),
        ]
    }
}
