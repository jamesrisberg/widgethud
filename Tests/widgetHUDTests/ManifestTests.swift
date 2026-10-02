import Foundation
import HUDKit
import XCTest
@testable import widgetHUD
import widgetHUDKit

/// The shipped machud.json and settings schemas are what MacHUD reads without launching
/// widgetHUD; keep them valid and in step with the code.
final class ManifestTests: XCTestCase {
    static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static var resources: URL { repo.appendingPathComponent("Sources/widgetHUD/Resources") }

    private func manifest() throws -> HUDManifest {
        try HUDManifest.decode(Data(contentsOf: Self.resources.appendingPathComponent(HUDManifest.fileName)))
    }

    private func schema(_ name: String) throws -> HUDSettingsSchema {
        try HUDSettingsSchema.decode(Data(contentsOf: Self.resources.appendingPathComponent(name)))
    }

    func testManifestFollowsTheConventions() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest.id, "xyz.machud.widgethud")
        XCTAssertEqual(manifest.socket, "widgethud", "socket name = CLI name = repo name")
    }

    func testAWidgetOnlyApp() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest.widgetPanels.map(\.id), ControlHost.widgetTypes)
        XCTAssertTrue(manifest.dockPanels.isEmpty, "no dock button")
        XCTAssertTrue(manifest.panels.allSatisfy { $0.kind == .widget })
        XCTAssertEqual(manifest.panel(id: "clock")?.widget?.sizes, [.small, .medium])
        XCTAssertEqual(manifest.panel(id: "weather")?.widget?.sizes, [.small, .medium, .large])
        XCTAssertEqual(manifest.panel(id: "calendar")?.widget?.sizes, [.small, .medium, .large])
        XCTAssertTrue(manifest.widgetPanels.allSatisfy { $0.widget?.multiple == true })
    }

    @MainActor
    func testBuiltinManifestMirrorsTheFile() throws {
        XCTAssertEqual(ControlHost.builtinManifest, try manifest())
    }

    func testAppSettingsSchemaMatchesAppSettings() throws {
        let name = try XCTUnwrap(try manifest().panels.first { $0.settingsSchema != nil }?.settingsSchema)
        XCTAssertEqual(name, "settings.json")
        let schema = try schema(name)
        XCTAssertEqual(Set(schema.settings.map(\.key)), AppSettings.keys)
        // Every option the schema offers parses, and its default is the code's.
        for field in schema.settings {
            for option in field.options { XCTAssertNoThrow(try AppSettings().applying([field.key: option.value]), field.key) }
        }
        XCTAssertEqual(try AppSettings().applying(schema.defaults.mapValues { "\($0)" }), AppSettings())
    }

    /// Each type's per-instance schema lists the keys the Kit reads, with the Kit's defaults.
    func testInstanceSchemasMatchTheKit() throws {
        let manifest = try manifest()
        func instanceSchema(_ type: String) throws -> HUDSettingsSchema {
            try schema(XCTUnwrap(manifest.panel(id: type)?.widget?.settingsSchema))
        }
        let clock = try instanceSchema("clock"), weather = try instanceSchema("weather"), calendar = try instanceSchema("calendar")
        XCTAssertEqual(Set(clock.settings.map(\.key)), ClockOptions.keys)
        XCTAssertEqual(Set(weather.settings.map(\.key)), WeatherOptions.keys)
        XCTAssertEqual(Set(calendar.settings.map(\.key)), CalendarOptions.keys)
        XCTAssertTrue(WeatherOptions.keys.isDisjoint(with: WeatherOptions.resolvedKeys), "lookup results stay out of the form")
        XCTAssertEqual(ClockOptions(settings: clock.defaults), ClockOptions(settings: [:]))
        XCTAssertEqual(WeatherOptions(settings: weather.defaults), WeatherOptions(settings: [:]))
        XCTAssertEqual(CalendarOptions(settings: calendar.defaults), CalendarOptions(settings: [:]))
        for schema in [clock, weather, calendar] { XCTAssertTrue(schema.settings.allSatisfy { $0.default != nil }) }
        XCTAssertEqual(calendar.field("daysAhead")?.min, Double(CalendarOptions.daysRange.lowerBound))
        XCTAssertEqual(calendar.field("daysAhead")?.max, Double(CalendarOptions.daysRange.upperBound))
        XCTAssertEqual(Set(clock.field("style")?.options.map(\.value) ?? []), Set(ClockOptions.Style.allCases.map(\.rawValue)))
    }

    func testInfoPlistAndEntitlements() throws {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "xyz.machud.widgethud")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "widgetHUD")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNotNil(plist["NSHumanReadableCopyright"])
        XCTAssertNotNil(plist["NSCalendarsFullAccessUsageDescription"], "EventKit full access needs a reason")
        let ent = try Data(contentsOf: Self.repo.appendingPathComponent("widgetHUD.entitlements"))
        let entitlements = try XCTUnwrap(PropertyListSerialization.propertyList(from: ent, format: nil) as? [String: Any])
        XCTAssertEqual(entitlements["com.apple.security.personal-information.calendars"] as? Bool, true,
                       "the hardened runtime refuses Calendar access without it")
    }
}
