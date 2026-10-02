import HUDKit
import SwiftUI

/// The look the three widgets share: white type on the family glass.
enum WidgetLook {
    static let padding: CGFloat = 14
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.4)
    /// The calendar's weekday red.
    static let accent = Color(red: 1, green: 0.42, blue: 0.38)
}

extension HUDWidgetContext {
    /// The instance's settings as plain JSON values, for the Kit's option readers.
    var jsonSettings: [String: Any] { settings.mapValues(\.jsonValue) }
}

extension Color {
    /// `#RRGGBB`; nil for anything else.
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A widget that cannot show its content yet: a symbol, a line, a hint and maybe one button.
struct WidgetMessage: View {
    var symbol: String
    var title: String
    var detail: String?
    var button: String?
    var compact = false
    var action: (() -> Void)?
    var busy = false

    var body: some View {
        VStack(spacing: compact ? 5 : 7) {
            if busy {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 22 : 26, weight: .regular))
                    .foregroundStyle(WidgetLook.secondary)
            }
            Text(title)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(WidgetLook.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetLook.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 3 : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let button, let action {
                Button(button, action: action)
                    .buttonStyle(WidgetButtonStyle())
                    .padding(.top, 2)
            }
        }
        .padding(WidgetLook.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small glass capsule button that reads on the dark glass.
struct WidgetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WidgetLook.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.28 : 0.18)))
            .contentShape(Capsule())
    }
}
