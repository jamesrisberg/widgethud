import AppKit
import HUDKit
import widgetHUDKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var control: ControlHost!
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--snapshot <path.png>`: render widgets with sample data, print the files and quit.
        // For docs and for checking the UI without Screen Recording permission.
        let args = CommandLine.arguments
        if args.contains("--snapshot") {
            do {
                for url in try Snapshot.run(arguments: args) { print(url.path) }
            } catch {
                FileHandle.standardError.write(Data("widgetHUD: snapshot failed: \(error)\n".utf8))
                exit(1)
            }
            NSApp.terminate(nil)
            return
        }

        if AppEnvironment.sampleData {
            model = AppModel.sample(settingsURL: AppEnvironment.settingsURL)
        } else {
            model = AppModel(settingsURL: AppEnvironment.settingsURL,
                             weather: WeatherStore(client: .live, cache: WeatherCache(url: AppEnvironment.weatherCacheURL)),
                             calendar: CalendarStore(provider: EventKitCalendars()))
        }
        control = ControlHost(model: model)
        control.start()
        setupStatusItem()
        // Menu bar consolidation: MacHUD shows this menu inside its own (`menu`, `menu-invoke`)
        // and the icon hides while it does. The `menuBar.consumed` opt-out is kept in
        // <home>/menubar.json, so it follows WIDGETHUD_HOME.
        control.router.menuProvider = { [weak self] in self?.statusItem.menu }
        HUDStatusItemPolicy.attach(statusItem, appID: control.manifest.id, store: .home(AppEnvironment.baseDirectory))
    }

    func applicationWillTerminate(_ notification: Notification) {
        control?.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // MenuBarIcon.png from hudkit/scripts/hud-icon.sh; the symbol under `swift run`.
        statusItem.button?.image = HUDStatusIcon.image(fallbackSymbol: "square.grid.2x2", accessibilityDescription: "widgetHUD")
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh Weather and Calendars", action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let access = NSMenuItem(title: "Calendar Access…", action: #selector(calendarAccess), keyEquivalent: "")
        access.target = self
        menu.addItem(access)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit widgetHUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateStatusLine()
    }

    /// Kept current when the menu opens (also when MacHUD lists it with `menu`).
    func menuNeedsUpdate(_ menu: NSMenu) { updateStatusLine() }

    private func updateStatusLine() {
        let n = control.widgets.instances.count
        statusLine.title = n == 0 ? "No widgets placed (add them in MacHUD)" : "\(n) widget\(n == 1 ? "" : "s") placed"
    }

    @objc private func refreshAll() {
        model.weather.refreshDue(force: true)
        model.calendar.reload()
    }

    /// The system prompt the first time; System Settings' Calendars pane once refused.
    @objc private func calendarAccess() {
        if model.calendar.access == .granted {
            model.calendar.openPrivacySettings()
        } else {
            model.calendar.requestAccess()
        }
    }
}
