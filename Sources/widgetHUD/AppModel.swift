import Foundation
import HUDKit
import widgetHUDKit

/// What the widgets share: the app-wide settings (written under `AppEnvironment`'s home) and the
/// weather and calendar stores.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: AppSettings

    let settingsURL: URL?
    let weather: WeatherStore
    let calendar: CalendarStore
    private var zoneObserver: NSObjectProtocol?

    /// `settingsURL` nil keeps settings in memory (tests).
    init(settingsURL: URL?, weather: WeatherStore, calendar: CalendarStore) {
        self.settingsURL = settingsURL
        self.weather = weather
        self.calendar = calendar
        settings = settingsURL.map(AppSettings.load(from:)) ?? AppSettings()
        // Clocks and agendas follow this Mac's zone; redraw them as soon as it changes.
        zoneObserver = NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSTimeZone.resetSystemTimeZone()
                self?.objectWillChange.send()
            }
        }
    }

    /// Sample weather and events (snapshots, `WIDGETHUD_SAMPLE_DATA`, tests).
    static func sample(settingsURL: URL? = nil) -> AppModel {
        AppModel(settingsURL: settingsURL, weather: .sample(), calendar: .sample())
    }

    func updateSettings(_ values: [String: String]) throws {
        let next = try settings.applying(values)
        if let settingsURL { try next.save(to: settingsURL) }
        settings = next
    }

    func temperatureUnit(instance: String?) -> TemperatureUnit {
        TemperatureUnit.resolve(instance: instance, app: settings.temperatureUnit, regional: .regional())
    }

    func timeFormat(instance: String?) -> TimeFormat {
        TimeFormat.resolve(instance: instance, app: settings.timeFormat, regional: .regional())
    }
}
