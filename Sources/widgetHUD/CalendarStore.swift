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
                          calendar: e.calendar?.title ?? "", color: e.calendar?.cgColor.flatMap(Self.hex))
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
/// instance filters by its own calendars and days). Active while at least one calendar widget
/// is shown: then it re-reads the access every minute (a grant in System Settings sends no
/// EventKit notification), and reloads when the database changes, when the day changes, after
/// wake and every five minutes. Loads run one at a time on a serial queue; a burst of changes
/// loads once, and only the newest load's events are kept.
@MainActor
final class CalendarStore: ObservableObject {
    static let window = 15
    static let tick: TimeInterval = 60
    /// Ticks between periodic reloads (five minutes).
    static let reloadTicks = 5

    @Published private(set) var access: CalendarAccess
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var loadedAt: Date?

    let provider: CalendarProviding
    var now: () -> Date = Date.init
    /// The instances still placed: shown instances gone from it are dropped on the next tick.
    var liveInstances: (() -> Set<String>)?
    /// The calendar widgets on screen.
    private(set) var shown: Set<String> = []
    private var requesting = false
    private var timer: Timer?
    private var ticks = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let queue = DispatchQueue(label: "widgethud.calendar", qos: .userInitiated)
    /// Bumped by every reload; a load whose number is no longer the newest is skipped or dropped.
    private let generation = Generation()

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

    var isActive: Bool { timer != nil }

    /// A calendar widget appeared. The first one starts the store: asks for access if never
    /// asked, then loads and keeps loading.
    func appeared(_ id: String) {
        shown.insert(id)
        guard !isActive else { return }
        ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
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

    /// A calendar widget went away; the last one stops the store.
    func disappeared(_ id: String) {
        shown.remove(id)
        if shown.isEmpty { stop() }
    }

    /// Once a minute while active: drops widgets that are gone, notices an access change, and
    /// reloads every `reloadTicks`.
    func tick() {
        if let live = liveInstances?() {
            for id in shown where !live.contains(id) { disappeared(id) }
            guard isActive else { return }
        }
        ticks += 1
        if provider.access != access || ticks % Self.reloadTicks == 0 { reload() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
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
        let mine = generation.next()
        guard access == .granted else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: now())
        let end = Agenda.horizon(days: Self.window, now: start)
        let provider = provider, generation = generation
        queue.async { [weak self] in
            // A newer reload is queued behind this one: let it do the work.
            guard generation.current == mine else { return }
            let events = provider.events(from: start, to: end)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation.current == mine else { return }
                    self.events = events
                    self.loadedAt = Date()
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
        var d: [String: Any] = ["access": access.rawValue, "events": events.count, "sample": provider is SampleCalendars,
                                "active": isActive, "widgets": shown.count]
        if let loadedAt { d["loadedAt"] = ISO8601DateFormatter().string(from: loadedAt) }
        return d
    }
}

/// A counter read from the load queue and bumped on the main thread.
private final class Generation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var current: Int { lock.withLock { value } }

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
