import Foundation

/// Isolation switches for tests and parallel instances (docs/CONTRACT.md):
///
/// - `WIDGETHUD_HOME`: base directory for everything widgetHUD writes (settings in
///   `<home>/preferences.json`); default `~/Library/Application Support/widgetHUD`.
/// - `WIDGETHUD_SOCKET`: socket name under MacHUD's sockets directory; default `widgethud`.
/// - `WIDGETHUD_NO_HOTKEYS`: set to skip registering global hotkeys.
enum AppEnvironment {
    static let environment = ProcessInfo.processInfo.environment

    static var isolatedHome: String? { nonEmpty("WIDGETHUD_HOME") }

    static var baseDirectory: URL {
        if let home = isolatedHome {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("widgetHUD", isDirectory: true)
    }

    static var settingsURL: URL { baseDirectory.appendingPathComponent("preferences.json") }

    static func socketName(default name: String) -> String { nonEmpty("WIDGETHUD_SOCKET") ?? name }

    static var hotKeysEnabled: Bool { environment["WIDGETHUD_NO_HOTKEYS"] == nil }

    private static func nonEmpty(_ key: String) -> String? {
        environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }
}
