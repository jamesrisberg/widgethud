import AppKit
import EventKit
import widgetHUDKit

/// Where the calendar widget's events come from: EventKit, or sample data.
protocol CalendarProviding: AnyObject, Sendable {
    var access: CalendarAccess { get }
    /// Asks for full access (the system prompt, once); returns the access afterwards.
    func requestAccess() async -> CalendarAccess
    /// Events overlapping `start..<end` in every calendar. Called off the main thread.
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    /// Called (on any thread) when the calendar database changes.
    var onChange: (() -> Void)? { get set }
}

/// The user's calendars through EventKit. The store is made lazily and nothing here prompts
/// until `requestAccess()`; reading the authorization status never does.
final class EventKitCalendars: CalendarProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _store: EKEventStore?
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    private var store: EKEventStore {
        lock.lock()
        defer { lock.unlock() }
        if let _store { return _store }
        let store = EKEventStore()
        _store = store
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { [weak self] _ in
            self?.onChange?()
        }
        return store
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        case .restricted: return .restricted
        case .denied, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        _ = try? await store.requestFullAccessToEvents()
        // A store made before the grant sees no calendars; start over with a fresh one.
        lock.withLock {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            _store = nil
        }
        return access
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let store = store
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { e in
            CalendarEvent(id: e.calendarItemIdentifier + "@" + String(e.startDate.timeIntervalSince1970),
                          title: e.title?.isEmpty == false ? e.title! : "Untitled",
                          start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                          calendar: e.calendar?.title ?? "", color: e.calendar?.cgColor.flatMap(Self.hex),
                          location: e.location)
        }
    }

    static func hex(_ color: CGColor) -> String? {
        guard let rgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        let c = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c[0], c[1], c[2])
    }
}

/// Sample events, readable unless made with another `access` (snapshots of the no-access states).
final class SampleCalendars: CalendarProviding, @unchecked Sendable {
    var onChange: (() -> Void)?
    let access: CalendarAccess

    init(access: CalendarAccess = .granted) {
        self.access = access
    }

    func requestAccess() async -> CalendarAccess { access }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        return SampleData.events(now: Date()).filter { $0.start < end && $0.end > start }
    }
}

/// The events every calendar widget draws from: the next two weeks of every calendar (each
/// instance filters by its own calendars and days), reloaded when the database changes, when
/// the day changes, after wake, and every five minutes.
@MainActor
final class CalendarStore: ObservableObject {
    static let window = 15
    static let reloadInterval: TimeInterval = 5 * 60

    @Published private(set) var access: CalendarAccess
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var loadedAt: Date?

    let provider: CalendarProviding
    var now: () -> Date = Date.init
    private var activated = false
    private var requesting = false
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(provider: CalendarProviding) {
        self.provider = provider
        access = provider.access
        provider.onChange = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reload() } }
        }
    }

    static func sample(access: CalendarAccess = .granted) -> CalendarStore {
        let store = CalendarStore(provider: SampleCalendars(access: access))
        if access == .granted {
            store.events = SampleData.events(now: Date())
            store.loadedAt = Date()
        }
        return store
    }

    /// The first calendar widget appeared: ask for access if never asked, then load and keep
    /// loading.
    func activate() {
        guard !activated else { return }
        activated = true
        timer = Timer.scheduledTimer(withTimeInterval: Self.reloadInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers.append((center, center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }))
        if provider.access == .notDetermined { requestAccess() } else { reload() }
    }

    /// Shows the system prompt (first time) or, once refused, opens the Calendars privacy pane.
    func requestAccess() {
        access = provider.access
        guard access == .notDetermined else {
            if access != .granted { openPrivacySettings() }
            reload()
            return
        }
        guard !requesting else { return }
        requesting = true
        Task { [weak self, provider] in
            let result = await provider.requestAccess()
            guard let self else { return }
            self.requesting = false
            self.access = result
            self.reload()
        }
    }

    func reload() {
        access = provider.access
        guard access == .granted else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: now())
        let end = Agenda.horizon(days: Self.window, now: start)
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let events = provider.events(from: start, to: end)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.events = events
                    self?.loadedAt = Date()
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    var json: [String: Any] {
        var d: [String: Any] = ["access": access.rawValue, "events": events.count, "sample": provider is SampleCalendars]
        if let loadedAt { d["loadedAt"] = ISO8601DateFormatter().string(from: loadedAt) }
        return d
    }
}
