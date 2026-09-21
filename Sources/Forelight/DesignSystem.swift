import AppKit
import SwiftUI

enum ForelightStyle {
    static let cardCorner: CGFloat = 10
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
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ForelightStyle.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
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
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        Divider()
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
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
                Spacer()
                Text(String(format: "%.2f%@", value, suffix))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: { onChanged($0) }), in: range)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
