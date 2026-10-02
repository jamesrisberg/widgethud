import Foundation

/// Isolation switches for tests and parallel instances (docs/CONTRACT.md):
///
/// - `WIDGETHUD_HOME`: base directory for everything widgetHUD writes (settings in
///   `<home>/preferences.json`, the weather cache in `<home>/weather-cache.json`); default
///   `~/Library/Application Support/widgetHUD`.
/// - `WIDGETHUD_SOCKET`: socket name under MacHUD's sockets directory; default `widgethud`.
/// - `WIDGETHUD_NO_HOTKEYS`: accepted for the family's isolation convention; widgetHUD registers
///   no global hotkeys (MacHUD's ⌃⌥W reveals widgets).
/// - `WIDGETHUD_SAMPLE_DATA`: set to show made-up weather and events: no network, no Calendar
///   access asked (test instances, demos).
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

    static var weatherCacheURL: URL { baseDirectory.appendingPathComponent("weather-cache.json") }

    static func socketName(default name: String) -> String { nonEmpty("WIDGETHUD_SOCKET") ?? name }

    static var sampleData: Bool { nonEmpty("WIDGETHUD_SAMPLE_DATA").map { $0 != "0" } ?? false }

    private static func nonEmpty(_ key: String) -> String? {
        environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }
}
