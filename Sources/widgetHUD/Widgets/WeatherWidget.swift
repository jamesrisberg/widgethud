import HUDKit
import SwiftUI
import widgetHUDKit

/// The weather widget (Open-Meteo): small (now, high/low), medium (+ the next hours), large
/// (+ the next five days). The place is a setting; widgetHUD looks it up and stores the
/// coordinates in the instance's settings, so the lookup happens once.
struct WeatherWidget: View {
    @ObservedObject var context: HUDWidgetContext
    @ObservedObject var model: AppModel
    @ObservedObject var weather: WeatherStore
    @State private var lookup: Lookup = .idle

    enum Lookup: Equatable {
        case idle, looking
        case notFound
        case failed(String)
    }

    /// What the lookup task depends on: it restarts when any of these change.
    private struct TaskKey: Equatable {
        var place: String
        var point: GeoPoint?
    }

    var body: some View {
        let options = WeatherOptions(settings: context.jsonSettings)
        content(options)
            .task(id: TaskKey(place: options.place, point: options.point)) { await resolve(options) }
    }

    @ViewBuilder
    private func content(_ options: WeatherOptions) -> some View {
        let compact = context.size == .small
        if options.place.isEmpty {
            WidgetMessage(symbol: "mappin.and.ellipse", title: "Set a place", detail: compact ? nil : "Pick the city this widget shows.",
                          button: "Choose…", compact: compact, action: { model.configure?(context) })
        } else if let point = options.point {
            let entry = weather.entry(for: point)
            if let report = entry.report {
                // Redrawn every minute so the hours move on and a report's age shows.
                TimelineView(.periodic(from: ClockWidget.minuteStart(), by: 60)) { timeline in
                    WeatherReportView(report: report, entry: entry, name: options.displayName, options: options,
                                      unit: model.temperatureUnit(instance: options.units),
                                      format: model.timeFormat(instance: nil), size: context.size, now: timeline.date)
                }
            } else if let error = entry.error, !entry.loading {
                WidgetMessage(symbol: "icloud.slash", title: "Weather unavailable", detail: error, compact: compact)
            } else {
                WidgetMessage(symbol: "cloud", title: options.displayName, detail: "Loading weather…", compact: compact, busy: true)
            }
        } else {
            switch lookup {
            case .notFound:
                WidgetMessage(symbol: "mappin.slash", title: "No place called “\(options.place)”",
                              detail: compact ? nil : "Try a city, or add a region: Portland, Maine.",
                              button: "Change…", compact: compact, action: { model.configure?(context) })
            case .failed(let why):
                WidgetMessage(symbol: "icloud.slash", title: "Can't look up \(options.place)", detail: "\(why). Trying again shortly.",
                              compact: compact)
            case .idle, .looking:
                WidgetMessage(symbol: "magnifyingglass", title: "Finding \(options.place)…", compact: compact, busy: true)
            }
        }
    }

    /// Tracks the place's forecast, looking the place up first when its coordinates are missing
    /// or stale (retrying every minute while offline).
    private func resolve(_ options: WeatherOptions) async {
        let id = context.instance
        guard !options.place.isEmpty else {
            weather.track(id, at: nil)
            lookup = .idle
            return
        }
        if let point = options.point {
            lookup = .idle
            weather.track(id, at: point)
            return
        }
        weather.track(id, at: nil)
        while !Task.isCancelled {
            lookup = .looking
            do {
                guard let found = try await weather.lookUp(options.place) else {
                    lookup = .notFound
                    return
                }
                let values = WeatherOptions.resolution(for: options.place, found: found).compactMapValues(HUDSettingValue.init(any:))
                try context.updateSettings(values)
                return
            } catch is CancellationError {
                return
            } catch {
                lookup = .failed(WeatherStore.describe(error))
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }
}

struct WeatherReportView: View {
    let report: WeatherReport
    let entry: WeatherStore.Entry
    let name: String
    let options: WeatherOptions
    let unit: TemperatureUnit
    let format: TimeFormat
    let size: HUDWidgetSize
    let now: Date

    var body: some View {
        switch size {
        case .small:
            current(large: false).padding(WidgetLook.padding)
        case .medium:
            HStack(alignment: .top, spacing: 12) {
                current(large: false).frame(width: 128)
                trailing
            }
            .padding(WidgetLook.padding)
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    current(large: true).frame(width: 128)
                    if options.showHourly { hours(count: 5) } else { Spacer(minLength: 0) }
                }
                .frame(height: 150)
                if options.showDaily {
                    Divider().overlay(Color.white.opacity(0.15))
                    days(count: 5)
                }
                Spacer(minLength: 0)
            }
            .padding(WidgetLook.padding)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if options.showHourly {
            hours(count: 5)
        } else if options.showDaily {
            days(count: 3, bars: false)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var today: WeatherReport.Day? { report.today(now: now) }
    private var condition: WeatherCondition { WeatherCondition(code: report.current.code, isDay: report.current.isDay) }

    private func current(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetLook.primary)
                    .lineLimit(1)
                if isStale {
                    Image(systemName: entry.error == "Offline" ? "wifi.slash" : "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetLook.tertiary)
                }
            }
            Text(unit.format(celsius: report.current.temperature))
                .font(.system(size: 44, weight: .light, design: .rounded))
                .foregroundStyle(WidgetLook.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: condition.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
            Text(condition.description)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetLook.primary)
                .lineLimit(1)
            if let today {
                Text("H \(unit.format(celsius: today.high))  L \(unit.format(celsius: today.low))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(WidgetLook.secondary)
            }
            if isStale {
                Text("Updated \(Age.text(since: report.fetchedAt, now: now))")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetLook.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var isStale: Bool { report.isOlder(than: WeatherStore.staleAfter, now: now) }

    private func hours(count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(report.nextHours(count, now: now).enumerated()), id: \.offset) { i, hour in
                VStack(spacing: 8) {
                    Text(i == 0 ? "Now" : format.hour(hour.time, zone: report.zone))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetLook.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: WeatherCondition(code: hour.code, isDay: hour.isDay).symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17))
                        .frame(height: 22)
                    Text(unit.format(celsius: i == 0 ? report.current.temperature : hour.temperature))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(WidgetLook.primary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `bars`: the low-to-high span bar between the temperatures (too narrow to read in medium).
    private func days(count: Int, bars: Bool = true) -> some View {
        let days = report.nextDays(count, now: now)
        let low = days.map(\.low).min() ?? 0, high = days.map(\.high).max() ?? 1
        return VStack(spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                HStack(spacing: 8) {
                    Text(i == 0 ? "Today" : weekday(day.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetLook.primary)
                        .frame(width: 44, alignment: .leading)
                    Image(systemName: WeatherCondition(code: day.code).symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                        .frame(width: 24)
                    Text(unit.format(celsius: day.low))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(WidgetLook.secondary)
                        .frame(width: 34, alignment: .trailing)
                    if bars {
                        RangeBar(low: low, high: high, from: day.low, to: day.high)
                            .frame(height: 4)
                    }
                    Text(unit.format(celsius: day.high))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(WidgetLook.primary)
                        .frame(width: 34, alignment: .leading)
                }
            }
        }
    }

    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = report.zone
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }
}

/// A day's low-to-high span within the range of the days shown.
private struct RangeBar: View {
    let low: Double, high: Double, from: Double, to: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(high - low, 1)
            let x0 = (from - low) / span * geo.size.width, x1 = (to - low) / span * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.75, blue: 1), Color(red: 1, green: 0.75, blue: 0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x1 - x0, 4))
                    .offset(x: x0)
            }
        }
    }
}
