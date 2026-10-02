import AppKit
import HUDKit
import widgetHUDKit

/// `--snapshot <path.png> [--type <type>] [--size <size>] [--editing]`: renders widgets with
/// sample data (no network, no Calendar access) over a dark stand-in for the glass.
///
/// With `--type` and `--size`, one widget goes to `<path.png>`. Otherwise every type at every
/// size, plus the states a user meets before a widget has data (no place, no Calendar access,
/// a world clock), go to `<stem>-<name>.png` beside it, and `<path.png>` is a contact sheet of
/// them all.
@MainActor
enum Snapshot {
    struct Shot {
        var name: String
        var type: String
        var size: HUDWidgetSize
        var settings: [String: HUDSettingValue] = [:]
        var calendarAccess: CalendarAccess = .granted
    }

    static let oslo: [String: HUDSettingValue] = [
        "place": .string("Oslo"), "latitude": .double(59.91), "longitude": .double(10.75),
        "resolvedPlace": .string("Oslo"), "resolvedName": .string("Oslo, Norway"),
    ]

    /// Every type × size, then the extra states.
    static var all: [Shot] {
        var shots: [Shot] = []
        for panel in ControlHost.builtinManifest.widgetPanels {
            for size in panel.widget?.sizes ?? [] {
                shots.append(Shot(name: "\(panel.id)-\(size.rawValue)", type: panel.id, size: size,
                                  settings: panel.id == "weather" ? oslo : [:]))
            }
        }
        shots.append(Shot(name: "clock-small-tokyo", type: "clock", size: .small,
                          settings: ["timeZone": .string("Tokyo"), "seconds": .bool(true)]))
        shots.append(Shot(name: "clock-medium-analog", type: "clock", size: .medium,
                          settings: ["timeZone": .string("New York"), "style": .string("analog")]))
        shots.append(Shot(name: "weather-small-noplace", type: "weather", size: .small))
        shots.append(Shot(name: "weather-medium-daily", type: "weather", size: .medium,
                          settings: oslo.merging(["showHourly": .bool(false)]) { $1 }))
        shots.append(Shot(name: "calendar-small-noaccess", type: "calendar", size: .small, calendarAccess: .notDetermined))
        shots.append(Shot(name: "calendar-medium-denied", type: "calendar", size: .medium, calendarAccess: .denied))
        return shots
    }

    /// Renders and returns the files written (the sheet last).
    static func run(arguments args: [String]) throws -> [URL] {
        guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return [] }
        let url = URL(fileURLWithPath: args[i + 1])
        let editing = args.contains("--editing")
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        if let type = value("--type") {
            let size = try value("--size").map { raw -> HUDWidgetSize in
                guard let s = HUDWidgetSize(rawValue: raw) else { throw HUDControlError.invalid("size must be small, medium, large or extraLarge") }
                return s
            } ?? ControlHost.builtinManifest.panel(id: type)?.widget?.defaultSize ?? .small
            try render(Shot(name: type, type: type, size: size, settings: type == "weather" ? oslo : [:]), editing: editing, to: url)
            return [url]
        }
        let stem = url.deletingPathExtension().path
        var written: [(Shot, URL)] = []
        for shot in all {
            let out = URL(fileURLWithPath: "\(stem)-\(shot.name).png")
            try render(shot, editing: editing, to: out)
            written.append((shot, out))
        }
        try writeSheet(written, to: url)
        return written.map(\.1) + [url]
    }

    static func render(_ shot: Shot, editing: Bool, to url: URL) throws {
        let model = AppModel(settingsURL: nil, weather: .sample(), calendar: .sample(access: shot.calendarAccess))
        let control = ControlHost(model: model, socketPath: NSTemporaryDirectory() + "widgethud-snapshot-\(UUID().uuidString).sock")
        try control.widgets.writeSnapshot(type: shot.type, size: shot.size, settings: shot.settings, editing: editing, to: url)
    }

    /// All shots on one dark sheet, a row per widget type in the order rendered, labelled.
    static func writeSheet(_ shots: [(Shot, URL)], to url: URL) throws {
        let gap: CGFloat = 24, label: CGFloat = 18, scale: CGFloat = 2
        var rows: [[(Shot, NSImage)]] = []
        for (shot, file) in shots {
            // Widget PNGs are 2x; draw them at their point size whatever DPI the file records.
            guard let image = NSImage(contentsOf: file), let px = image.representations.first else { continue }
            image.size = CGSize(width: CGFloat(px.pixelsWide) / scale, height: CGFloat(px.pixelsHigh) / scale)
            if let last = rows.last?.last, last.0.type == shot.type, rows[rows.count - 1].count < 5 {
                rows[rows.count - 1].append((shot, image))
            } else {
                rows.append([(shot, image)])
            }
        }
        let width = rows.map { row in row.reduce(gap) { $0 + $1.1.size.width + gap } }.max() ?? gap
        let height = rows.reduce(gap) { $0 + ($1.map(\.1.size.height).max() ?? 0) + label + gap }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = CGSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        NSColor(calibratedWhite: 0.3, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: width, height: height).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                    .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1)]
        var top = height - gap
        for row in rows {
            let rowHeight = row.map(\.1.size.height).max() ?? 0
            var x = gap
            for (shot, image) in row {
                (shot.name as NSString).draw(at: CGPoint(x: x, y: top - 13), withAttributes: attrs)
                image.draw(in: CGRect(x: x, y: top - label - image.size.height, width: image.size.width, height: image.size.height))
                x += image.size.width + gap
            }
            top -= rowHeight + label + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
