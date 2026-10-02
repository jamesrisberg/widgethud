import Foundation
import HUDKit
import XCTest
@testable import widgetHUD
import widgetHUDKit

@MainActor
final class ControlHostTests: XCTestCase {
    private var host: ControlHost!
    private var events: [[String: Any]] = []

    override func setUp() async throws {
        // Never started: the router is driven directly, so no socket is created.
        host = ControlHost(model: .sample(), socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock",
                           resources: ManifestTests.resources)
        host.widgets.presentsWindows = false
        events = []
        host.widgets.onEvent = { [unowned self] in self.events.append($0) }
    }

    override func tearDown() async throws {
        _ = call("widget", ["action": "sync", "instances": "[]"])  // closes the test windows
        host = nil
    }

    private func call(_ verb: String, _ args: [String: String] = [:]) -> [String: Any] {
        var out: [String: Any] = [:]
        host.router.handle(verb, args: args) { out = $0 }
        return out
    }

    private func callAsync(_ verb: String, _ args: [String: String]) async -> [String: Any] {
        await withCheckedContinuation { cont in host.router.handle(verb, args: args) { cont.resume(returning: $0) } }
    }

    func testHelloListsTheWidgetTypesAndTheWidgetVerb() {
        let hello = call("hello")
        XCTAssertEqual(hello["ok"] as? Bool, true)
        XCTAssertEqual(hello["hudkit"] as? String, HUDKit.version)
        XCTAssertEqual(hello["app"] as? String, "xyz.machud.widgethud")
        XCTAssertTrue((hello["verbs"] as? [String])?.contains("widget") == true)
        let panels = hello["panels"] as? [[String: Any]] ?? []
        XCTAssertEqual(panels.map { $0["id"] as? String }, ["clock", "weather", "calendar"])
        XCTAssertTrue(panels.allSatisfy { $0["kind"] as? String == "widget" })
    }

    func testNoDockPanels() {
        XCTAssertEqual((call("state")["panels"] as? [Any])?.count, 0)
        XCTAssertEqual(call("panel", ["id": "clock", "action": "show"])["error"] as? String, "no such panel")
    }

    func testEveryTypeAtEverySizeCanBePlacedListedAndRemoved() {
        var n = 0
        for panel in ControlHost.builtinManifest.widgetPanels {
            for size in panel.widget?.sizes ?? [] {
                n += 1
                let id = "\(panel.id)-\(size.rawValue)"
                let created = call("widget", ["action": "create", "instance": id, "type": panel.id, "size": size.rawValue,
                                              "frame": "\(n * 10),40,\(Int(size.points().width)),\(Int(size.points().height))"])
                XCTAssertEqual(created["ok"] as? Bool, true, "\(id): \(created)")
            }
        }
        let list = call("widget", ["action": "list"])
        XCTAssertEqual((list["instances"] as? [Any])?.count, n)
        XCTAssertEqual(list["types"] as? [String], ControlHost.widgetTypes)
        XCTAssertEqual(call("widget", ["action": "remove", "instance": "clock-small"])["removed"] as? String, "clock-small")
        XCTAssertEqual((call("widget", ["action": "list"])["instances"] as? [Any])?.count, n - 1)
    }

    func testSizesTheTypeDoesNotDeclareAreRefused() {
        let reply = call("widget", ["action": "create", "instance": "c", "type": "clock", "size": "large"])
        XCTAssertEqual(reply["error"] as? String, "clock size must be one of small, medium")
    }

    func testInstanceSettingsAreTypedByTheSchema() throws {
        let reply = call("widget", ["action": "create", "instance": "c", "type": "clock",
                                    "settings": #"{"timeZone": "Tokyo", "seconds": "on"}"#])
        XCTAssertEqual(reply["ok"] as? Bool, true, "\(reply)")
        let settings = try XCTUnwrap(host.widgets.instance("c")?.settings)
        XCTAssertEqual(settings["seconds"], .bool(true))
        XCTAssertEqual(settings["timeZone"], .string("Tokyo"))
        let bad = call("widget", ["action": "update", "instance": "c", "settings": #"{"style": "sundial"}"#])
        XCTAssertEqual(bad["ok"] as? Bool, false)
        let days = call("widget", ["action": "create", "instance": "k", "type": "calendar", "settings": #"{"daysAhead": 30}"#])
        XCTAssertEqual(days["error"] as? String, "daysAhead must be at most 14")
    }

    func testSchemaAndSync() {
        let schema = call("widget", ["action": "schema", "type": "weather"])
        let keys = ((schema["schema"] as? [String: Any])?["settings"] as? [[String: Any]])?.compactMap { $0["key"] as? String }
        XCTAssertEqual(Set(keys ?? []), WeatherOptions.keys)
        let sync = call("widget", ["action": "sync", "editing": "on", "instances":
            #"[{"instance":"w","type":"weather","size":"medium","frame":[0,0,356,170],"settings":{"place":"Oslo","latitude":59.91,"longitude":10.75,"resolvedPlace":"Oslo"}},{"instance":"x","type":"radar"}]"#])
        XCTAssertEqual((sync["instances"] as? [Any])?.count, 1)
        XCTAssertEqual((sync["rejected"] as? [Any])?.count, 1)
        XCTAssertEqual(sync["editing"] as? Bool, true)
        XCTAssertEqual(host.widgets.instance("w")?.settings["latitude"], .double(59.91), "lookup results survive a sync")
    }

    func testEditAndReveal() {
        XCTAssertEqual(call("widget", ["action": "edit", "state": "on"])["editing"] as? Bool, true)
        XCTAssertEqual(call("widget", ["action": "reveal", "on": "1"])["revealed"] as? Bool, true)
        XCTAssertEqual(call("widget", ["action": "edit", "state": "off"])["editing"] as? Bool, false)
    }

    func testSetAPlaceAsksMacHUDForTheInstanceSettings() throws {
        _ = call("widget", ["action": "create", "instance": "w", "type": "weather"])
        let context = try XCTUnwrap(host.widgets.context(for: "w"))
        context.configure()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["change"] as? String, "configure")
        XCTAssertEqual(events.first?["instance"] as? String, "w")
        XCTAssertEqual(events.first?["type"] as? String, "weather")
    }

    func testAppSettings() {
        XCTAssertEqual(call("settings", ["action": "set", "temperatureUnit": "celsius"])["ok"] as? Bool, true)
        XCTAssertEqual(host.model.settings.temperatureUnit, .celsius)
        XCTAssertEqual(host.model.temperatureUnit(instance: "app"), .celsius)
        XCTAssertEqual(host.model.temperatureUnit(instance: "fahrenheit"), .fahrenheit)
        XCTAssertEqual(call("settings", ["action": "set", "temperatureUnit": "kelvin"])["ok"] as? Bool, false)
        XCTAssertEqual((call("settings", ["action": "get"])["settings"] as? [String: Any])?["timeFormat"] as? String, "auto")
    }

    func testActions() async {
        XCTAssertEqual(call("action", ["name": "refresh"])["ok"] as? Bool, true)
        let status = call("action", ["name": "status"])
        XCTAssertEqual(status["ok"] as? Bool, true)
        XCTAssertEqual((status["calendar"] as? [String: Any])?["access"] as? String, "granted")
        XCTAssertEqual(call("action", ["name": "places"])["error"] as? String, "places needs query=<place>")
        let places = await callAsync("action", ["name": "places", "query": "Bergen, Norway"])
        XCTAssertEqual(places["ok"] as? Bool, true)
        XCTAssertEqual((places["best"] as? [String: Any])?["name"] as? String, "Bergen, Norway")
        XCTAssertEqual((call("action", ["name": "nope"])["error"] as? String)?.hasPrefix("unknown action nope"), true)
    }
}
