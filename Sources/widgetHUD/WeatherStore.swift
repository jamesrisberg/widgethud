import AppKit
import widgetHUDKit

/// Forecasts for every place a weather widget shows, shared by instances at the same place.
/// Each is refreshed every 15 minutes while a widget shows it, kept on disk (`WeatherCache`) so
/// widgets have something at launch and offline, and retried every few minutes after a failure.
@MainActor
final class WeatherStore: ObservableObject {
    struct Entry: Equatable {
        var report: WeatherReport?
        /// Why the last fetch failed; nil after a success.
        var error: String?
        var loading = false
        var lastAttempt: Date?
    }

    static let refreshInterval: TimeInterval = 15 * 60
    static let retryInterval: TimeInterval = 2 * 60
    /// A report older than this is shown with its age.
    static let staleAfter: TimeInterval = 45 * 60

    @Published private(set) var entries: [String: Entry] = [:]
    /// Instance id → the place it shows.
    private(set) var tracked: [String: GeoPoint] = [:]

    /// nil: sample data (no network).
    let client: WeatherClient?
    let cache: WeatherCache?
    var now: () -> Date = Date.init
    /// The instances still placed, to forget places no widget shows any more.
    var liveInstances: (() -> Set<String>)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(client: WeatherClient?, cache: WeatherCache?) {
        self.client = client
        self.cache = cache
        for (key, report) in cache?.load() ?? [:] { entries[key] = Entry(report: report) }
    }

    static func sample() -> WeatherStore { WeatherStore(client: nil, cache: nil) }

    var isSample: Bool { client == nil }

    /// Starts the periodic refresh check (once a minute, and on wake).
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

    func entry(for point: GeoPoint) -> Entry {
        if isSample { return Entry(report: SampleData.weather(now: now())) }
        return entries[point.key] ?? Entry()
    }

    /// Instance `id` shows `point` (nil: nothing yet). Fetches when the place has no fresh report.
    func track(_ id: String, at point: GeoPoint?) {
        tracked[id] = point
        if let point { refreshIfDue(point) }
    }

    func untrack(_ id: String) { tracked[id] = nil }

    /// Fetches every tracked place whose report is due (or every one with `force`).
    func refreshDue(force: Bool = false) {
        if let live = liveInstances?() { tracked = tracked.filter { live.contains($0.key) } }
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
    }

    private func saveCache() {
        guard let cache else { return }
        let reports = entries.compactMapValues(\.report)
        do { try cache.save(reports) } catch { NSLog("widgetHUD: weather cache not saved: %@", "\(error)") }
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
            "instances": tracked.keys.sorted(),
        ]
    }
}
