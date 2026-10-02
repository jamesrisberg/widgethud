import AppKit
import HUDKit
import widgetHUDKit

/// widgetHUD's side of the MacHUD contract: serves the control socket at
/// `~/Library/Application Support/MacHUD/sockets/widgethud.sock` through HUDKit's router. A
/// widget-only app: no dock panel, three widget types served by `widgets`, app-wide settings,
/// and a few actions. See docs/CONTRACT.md for the verbs.
@MainActor
final class ControlHost: HUDPanelHost {
    nonisolated static let actions = ["refresh", "places", "status"]
    nonisolated static let widgetTypes = ["clock", "weather", "calendar"]

    /// Used when running outside a bundle (`swift run`, tests); mirrors Resources/machud.json.
    static let builtinManifest = HUDManifest(id: "xyz.machud.widgethud", name: "widgetHUD", socket: "widgethud", panels: [
        HUDManifest.Panel(id: "clock", title: "Clock", symbol: "clock", settingsSchema: "settings.json", kind: .widget,
                          widget: HUDWidgetSpec(sizes: [.small, .medium], defaultSize: .small, multiple: true, refresh: 1,
                                                settingsSchema: "clock.widget.json")),
        HUDManifest.Panel(id: "weather", title: "Weather", symbol: "cloud.sun", kind: .widget,
                          widget: HUDWidgetSpec(sizes: [.small, .medium, .large], defaultSize: .small, multiple: true, refresh: 900,
                                                settingsSchema: "weather.widget.json")),
        HUDManifest.Panel(id: "calendar", title: "Calendar", symbol: "calendar", kind: .widget,
                          widget: HUDWidgetSpec(sizes: [.small, .medium, .large], defaultSize: .medium, multiple: true, refresh: 60,
                                                settingsSchema: "calendar.widget.json")),
    ], iconName: "square.grid.2x2")

    let manifest: HUDManifest
    let server: HUDSocketServer
    private(set) var router: HUDControlRouter!
    let model: AppModel
    let widgets: HUDWidgetHost

    /// `resources`: a directory to read the per-instance settings schemas from when not running
    /// from a bundle (tests, `swift run`); the bundle's are used otherwise.
    init(model: AppModel, socketPath: String? = nil, resources: URL? = nil) {
        self.model = model
        let bundled = HUDManifest.main
        manifest = bundled ?? Self.builtinManifest
        server = HUDSocketServer(path: socketPath ?? HUDSocket.path(for: AppEnvironment.socketName(default: manifest.socket)),
                                 label: "widgethud.socket")
        widgets = HUDWidgetHost(manifest: manifest)
        if bundled == nil, let resources {
            for panel in manifest.widgetPanels {
                guard let name = panel.widget?.settingsSchema,
                      let data = try? Data(contentsOf: resources.appendingPathComponent(name)) else { continue }
                widgets.schemas[panel.id] = try? HUDSettingsSchema.decode(data)
            }
        }
        widgets.register("clock") { [model] in ClockWidget(context: $0, model: model) }
        widgets.register("weather") { [model] in WeatherWidget(context: $0, model: model, weather: model.weather) }
        widgets.register("calendar") { [model] in CalendarWidget(context: $0, model: model, calendar: model.calendar) }
        router = HUDControlRouter(host: self, server: server, manifest: manifest)
        // MacHUD sends `widget sync` as soon as it connects, so the host is in place first.
        router.widgetHost = widgets
        // The "Set a place" button asks MacHUD for the instance's settings, as the edit-mode
        // gear does (`change: configure`).
        model.configure = { [weak widgets] context in
            widgets?.onEvent?(["instance": context.instance, "type": context.type, "change": "configure"])
        }
        model.weather.liveInstances = { [weak widgets] in Set(widgets?.instances.map(\.id) ?? []) }
    }

    func start() {
        router.install()
        if !server.start() { NSLog("widgetHUD: control socket failed to start at %@", server.path) }
        model.weather.start()
    }

    func stop() { server.stop() }

    // MARK: - HUDPanelHost

    var panelDescriptors: [HUDManifest.Panel] { manifest.panels }

    /// No dock panels: every panel is a widget type, placed with `widget create`.
    var panelStates: [HUDPanelState] { [] }

    func showPanel(_ id: String) throws { throw HUDControlError.noSuchPanel(id) }
    func hidePanel(_ id: String) throws { throw HUDControlError.noSuchPanel(id) }

    // MARK: Settings

    func settings() -> [String: Any] { model.settings.json }

    func updateSettings(_ values: [String: String]) throws {
        do {
            try model.updateSettings(values)
        } catch let error as AppSettings.SettingsError {
            throw HUDControlError.invalid(error.description)
        }
        router.publishState()
    }

    // MARK: Actions

    func performAction(_ name: String, args: [String: String], done: @escaping ([String: Any]) -> Void) {
        switch name {
        case "refresh":
            model.weather.refreshDue(force: true)
            model.calendar.reload()
            done(["ok": true, "weather": model.weather.tracked.count, "calendar": model.calendar.access.rawValue])
        case "places":
            let query = (args["query"] ?? args["place"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                done(["ok": false, "error": "places needs query=<place>"])
                return
            }
            let weather = model.weather
            Task {
                do {
                    let found = try await weather.search(query)
                    let best = GeoPlace.best(found, qualifiers: GeoPlace.query(query).qualifiers)
                    done(["ok": true, "query": query, "best": best.map(Self.placeJSON) ?? NSNull(), "places": found.map(Self.placeJSON)])
                } catch {
                    done(["ok": false, "error": WeatherStore.describe(error)])
                }
            }
        case "status":
            done(["ok": true, "instances": widgets.instances.count, "editing": widgets.isEditing, "revealed": widgets.isRevealed,
                  "weather": model.weather.json, "calendar": model.calendar.json, "settings": model.settings.json])
        default:
            done(["ok": false, "error": "unknown action \(name) (\(Self.actions.joined(separator: ", ")))"])
        }
    }

    static func placeJSON(_ p: GeoPlace) -> [String: Any] {
        var d: [String: Any] = ["name": p.displayName, "latitude": p.latitude, "longitude": p.longitude]
        if let zone = p.timeZone { d["timeZone"] = zone }
        return d
    }

    func quit() { NSApp.terminate(nil) }
}
