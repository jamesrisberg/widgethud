import Foundation
import HUDKit
import XCTest
@testable import widgetHUD
import widgetHUDKit

/// The shipped machud.json and settings.json are what MacHUD reads without launching
/// widgetHUD; keep them valid and in step with the code.
final class ManifestTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/widgetHUD/Resources")
    }

    private func manifest() throws -> HUDManifest {
        try HUDManifest.decode(Data(contentsOf: resources.appendingPathComponent(HUDManifest.fileName)))
    }

    func testManifestFollowsTheConventions() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest.id, "xyz.machud.widgethud")
        XCTAssertEqual(manifest.socket, "widgethud", "socket name = CLI name = repo name")
        let panel = try XCTUnwrap(manifest.panel(id: ControlHost.panelID))
        XCTAssertEqual(panel.kind, .hover)
    }

    @MainActor
    func testBuiltinManifestMirrorsTheFile() throws {
        XCTAssertEqual(ControlHost.builtinManifest, try manifest())
    }

    func testSettingsSchemaMatchesAppSettings() throws {
        let name = try XCTUnwrap(try manifest().panels.first?.settingsSchema)
        let data = try Data(contentsOf: resources.appendingPathComponent(name))
        let schema = try HUDSettingsSchema.decode(data)
        XCTAssertEqual(Set(schema.settings.map(\.key)), AppSettings.keys)
    }

    func testInfoPlist() throws {
        let data = try Data(contentsOf: resources.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "xyz.machud.widgethud")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "widgetHUD")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNotNil(plist["NSHumanReadableCopyright"])
    }
}
