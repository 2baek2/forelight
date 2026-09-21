import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum ForelightStyle {
    static let cardCorner: CGFloat = 10

    // Vorssaint default palette (its :root values).
    static let accent = Color(hex: 0x0A84FF)
    static let green = Color(hex: 0x32D74B)
    static let cyan = Color(hex: 0x64D2FF)
    static let mint = Color(hex: 0x66D4CF)
    static let orange = Color(hex: 0xFF9F0A)
    static let pink = Color(hex: 0xFF375F)

    static let accentSoft = accent.opacity(0.18)

    // Surfaces follow Vorssaint's dark popover, with a matching light variant.
    static let windowBackground = dynamic(
        dark: 0x26262A,
        light: 0xF5F5F7
    )

    static var windowNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(hex: 0x26262A)
                : NSColor(hex: 0xF5F5F7)
        }
    }

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.05)
    })

    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.12)
    })

    static let hairline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.10)
    })

    static let text = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor.white.withAlphaComponent(0.96)
            : NSColor.black.withAlphaComponent(0.90)
    })

    static let muted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(hex: 0xEBEBF5).withAlphaComponent(0.60)
            : NSColor.black.withAlphaComponent(0.55)
    })

    static let muted2 = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(hex: 0xEBEBF5).withAlphaComponent(0.38)
            : NSColor.black.withAlphaComponent(0.35)
    })

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: ForelightStyle.cardCorner, style: .continuous)
                .fill(ForelightStyle.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ForelightStyle.cardCorner, style: .continuous)
                .strokeBorder(ForelightStyle.cardBorder, lineWidth: 1)
        )
    }
}

struct CardRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    private let control: Control

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(ForelightStyle.muted2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(ForelightStyle.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ForelightStyle.muted)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(ForelightStyle.hairline)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(ForelightStyle.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(ForelightStyle.muted)
            .padding(.leading, 2)
    }
}

struct SliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let suffix: String
    let onChanged: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(ForelightStyle.text)
                Spacer()
                Text(String(format: "%.2f%@", value, suffix))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ForelightStyle.muted)
            }
            Slider(value: Binding(get: { value }, set: { onChanged($0) }), in: range)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
