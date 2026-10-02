import HUDKit
import SwiftUI
import widgetHUDKit

/// The clock widget: small (analog face by default) or medium (digital with the date by
/// default), in any time zone, so several instances make a world clock.
struct ClockWidget: View {
    @ObservedObject var context: HUDWidgetContext
    @ObservedObject var model: AppModel

    var body: some View {
        let options = ClockOptions(settings: context.jsonSettings)
        let format = model.timeFormat(instance: options.timeFormat)
        if let zone = options.zone() {
            TimelineView(.periodic(from: Self.minuteStart(), by: options.seconds ? 1 : 60)) { timeline in
                ClockContent(date: timeline.date, zone: zone, options: options, format: format, small: context.size == .small)
            }
        } else {
            WidgetMessage(symbol: "globe", title: "Unknown time zone", detail: "“\(options.timeZone)”: try a city or a name like Europe/Oslo.",
                          compact: context.size == .small)
        }
    }

    /// Ticks start on a whole minute so a clock without seconds turns over on time.
    static func minuteStart(_ now: Date = Date()) -> Date {
        Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}

private struct ClockContent: View {
    let date: Date
    let zone: TimeZone
    let options: ClockOptions
    let format: TimeFormat
    let small: Bool

    private var label: String { options.displayLabel(zone: zone) }
    private var offset: String? { options.isLocal ? nil : ClockOptions.offsetLabel(zone, at: date) }

    var body: some View {
        if small {
            if options.isAnalog(small: true) { smallAnalog } else { smallDigital }
        } else {
            if options.isAnalog(small: false) { mediumAnalog } else { mediumDigital }
        }
    }

    private var smallAnalog: some View {
        VStack(spacing: 6) {
            AnalogDial(date: date, zone: zone, seconds: options.seconds)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            caption
        }
        .padding(.top, 12)
        .padding([.horizontal, .bottom], WidgetLook.padding)
    }

    private var smallDigital: some View {
        VStack(alignment: .leading, spacing: 2) {
            caption
            Spacer(minLength: 0)
            timeText(size: options.seconds ? 30 : 40)
            Text(dateText("EEE d MMM"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WidgetLook.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetLook.padding)
    }

    private var mediumDigital: some View {
        VStack(alignment: .leading, spacing: 2) {
            caption
            Spacer(minLength: 0)
            timeText(size: 56)
            Text(dateText("EEEE d MMMM"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WidgetLook.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetLook.padding + 2)
    }

    private var mediumAnalog: some View {
        HStack(spacing: 16) {
            AnalogDial(date: date, zone: zone, seconds: options.seconds)
                .frame(width: 136, height: 136)
            VStack(alignment: .leading, spacing: 4) {
                caption
                timeText(size: 30)
                Text(dateText("EEEE d MMMM"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WidgetLook.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WidgetLook.padding + 2)
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetLook.primary)
                .lineLimit(1)
            if let offset {
                Text(offset)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(WidgetLook.tertiary)
            }
        }
    }

    private func timeText(size: CGFloat) -> some View {
        Text(format.time(date, zone: zone, seconds: options.seconds))
            .font(.system(size: size, weight: .light, design: .rounded).monospacedDigit())
            .foregroundStyle(WidgetLook.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func dateText(_ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f.string(from: date)
    }
}

/// A clock face: twelve ticks, hour and minute hands, an optional second hand.
struct AnalogDial: View {
    let date: Date
    let zone: TimeZone
    let seconds: Bool

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side / 2
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side)),
                     with: .color(.white.opacity(0.08)))
            for i in 0..<12 {
                let angle = Double(i) / 12 * 2 * .pi
                let major = i % 3 == 0
                let outer = radius - 5, inner = outer - (major ? 9 : 5)
                var tick = Path()
                tick.move(to: point(center, angle, inner))
                tick.addLine(to: point(center, angle, outer))
                ctx.stroke(tick, with: .color(.white.opacity(major ? 0.85 : 0.45)),
                           style: StrokeStyle(lineWidth: major ? 2.5 : 1.5, lineCap: .round))
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let s = Double(c.second ?? 0)
            let m = Double(c.minute ?? 0) + s / 60
            let h = Double((c.hour ?? 0) % 12) + m / 60
            hand(ctx, center, angle: h / 12 * 2 * .pi, length: radius * 0.5, width: 4.5, color: .white)
            hand(ctx, center, angle: m / 60 * 2 * .pi, length: radius * 0.74, width: 3, color: .white)
            if seconds {
                hand(ctx, center, angle: s / 60 * 2 * .pi, length: radius * 0.82, width: 1.2, color: WidgetLook.accent)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
                     with: .color(seconds ? WidgetLook.accent : .white))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The point `length` from `center` at `angle` (0 = twelve o'clock, clockwise).
    private func point(_ center: CGPoint, _ angle: Double, _ length: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
    }

    private func hand(_ ctx: GraphicsContext, _ center: CGPoint, angle: Double, length: CGFloat, width: CGFloat, color: Color) {
        var p = Path()
        p.move(to: point(center, angle + .pi, length * 0.14))
        p.addLine(to: point(center, angle, length))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
