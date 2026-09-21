import SwiftUI

struct MenuPanelView: View {
    let isEnabled: Bool
    let currentApplicationName: String?
    let currentApplicationIsExcluded: Bool
    let intensity: Double
    let hideWhileMoving: Bool
    let onToggleEnabled: (Bool) -> Void
    let onIntensityChanged: (Double) -> Void
    let onToggleMoving: (Bool) -> Void
    let onToggleExclusion: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    init(
        isEnabled: Bool,
        currentApplicationName: String?,
        currentApplicationIsExcluded: Bool,
        intensity: Double,
        hideWhileMoving: Bool,
        onToggleEnabled: @escaping (Bool) -> Void,
        onIntensityChanged: @escaping (Double) -> Void,
        onToggleMoving: @escaping (Bool) -> Void,
        onToggleExclusion: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.currentApplicationName = currentApplicationName
        self.currentApplicationIsExcluded = currentApplicationIsExcluded
        self.intensity = intensity
        self.hideWhileMoving = hideWhileMoving
        self.onToggleEnabled = onToggleEnabled
        self.onIntensityChanged = onIntensityChanged
        self.onToggleMoving = onToggleMoving
        self.onToggleExclusion = onToggleExclusion
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forelight")
                        .font(.headline)
                    Text(isEnabled ? "Focus mode is on" : "Focus mode is paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { isEnabled }, set: { value in onToggleEnabled(value) }))
                    .labelsHidden()
            }

            Divider()

            IntensityControl(value: intensity, onChanged: onIntensityChanged)

            Toggle("Hide while moving a window", isOn: Binding(get: { hideWhileMoving }, set: { value in onToggleMoving(value) }))

            if let currentApplicationName {
                Button(action: onToggleExclusion) {
                    Label(
                        currentApplicationIsExcluded ? "Include " + currentApplicationName : "Exclude " + currentApplicationName,
                        systemImage: currentApplicationIsExcluded ? "eye" : "eye.slash"
                    )
                }
                .buttonStyle(.borderless)
            }

            Divider()

            HStack {
                Button("Settings…", action: onOpenSettings)
                Spacer()
                Button("Quit", action: onQuit)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct SettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case focus = "Focus"
        case exceptions = "Exceptions"
        case advanced = "Advanced"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .focus: return "viewfinder"
            case .exceptions: return "eye.slash"
            case .advanced: return "gearshape"
            }
        }
    }

    let isEnabled: Bool
    let currentApplicationName: String?
    let currentApplicationIsExcluded: Bool
    let accessibilityTrusted: Bool
    let intensity: Double
    let hideWhileMoving: Bool
    let fadeDuration: Double
    let restoreDelay: Double
    let onToggleEnabled: (Bool) -> Void
    let onIntensityChanged: (Double) -> Void
    let onToggleMoving: (Bool) -> Void
    let onFadeDurationChanged: (Double) -> Void
    let onRestoreDelayChanged: (Double) -> Void
    let onToggleExclusion: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    @State private var selectedSection: Section = .general
    @State private var enabledValue: Bool
    @State private var hideWhileMovingValue: Bool
    @State private var fadeDurationValue: Double
    @State private var restoreDelayValue: Double

    init(
        isEnabled: Bool,
        currentApplicationName: String?,
        currentApplicationIsExcluded: Bool,
        accessibilityTrusted: Bool,
        intensity: Double,
        hideWhileMoving: Bool,
        fadeDuration: Double,
        restoreDelay: Double,
        onToggleEnabled: @escaping (Bool) -> Void,
        onIntensityChanged: @escaping (Double) -> Void,
        onToggleMoving: @escaping (Bool) -> Void,
        onFadeDurationChanged: @escaping (Double) -> Void,
        onRestoreDelayChanged: @escaping (Double) -> Void,
        onToggleExclusion: @escaping () -> Void,
        onOpenAccessibilitySettings: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.currentApplicationName = currentApplicationName
        self.currentApplicationIsExcluded = currentApplicationIsExcluded
        self.accessibilityTrusted = accessibilityTrusted
        self.intensity = intensity
        self.hideWhileMoving = hideWhileMoving
        self.fadeDuration = fadeDuration
        self.restoreDelay = restoreDelay
        self.onToggleEnabled = onToggleEnabled
        self.onIntensityChanged = onIntensityChanged
        self.onToggleMoving = onToggleMoving
        self.onFadeDurationChanged = onFadeDurationChanged
        self.onRestoreDelayChanged = onRestoreDelayChanged
        self.onToggleExclusion = onToggleExclusion
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        _enabledValue = State(initialValue: isEnabled)
        _hideWhileMovingValue = State(initialValue: hideWhileMoving)
        _fadeDurationValue = State(initialValue: fadeDuration)
        _restoreDelayValue = State(initialValue: restoreDelay)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Section.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(selectedSection.rawValue)
                        .font(.title2.weight(.semibold))
                    detailView
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    Toggle("Enable Forelight", isOn: Binding(
                        get: { enabledValue },
                        set: { value in enabledValue = value; onToggleEnabled(value) }
                    ))
                        .padding(8)
                }
                GroupBox("Keyboard shortcut") {
                    HStack {
                        Text("Toggle focus mode")
                        Spacer()
                        Text("⌥⌘F")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                Text("The menu bar icon shows whether focus mode is active. The shortcut works from any app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .focus:
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Overlay") {
                    VStack(alignment: .leading, spacing: 12) {
                        IntensityControl(value: intensity, onChanged: onIntensityChanged)
                        Toggle("Hide while moving a window", isOn: Binding(
                            get: { hideWhileMovingValue },
                            set: { value in hideWhileMovingValue = value; onToggleMoving(value) }
                        ))
                    }
                    .padding(8)
                }
                GroupBox("Window movement") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingSlider(title: "Fade animation", value: fadeDurationValue, range: 0...0.35, suffix: "s") { value in
                            fadeDurationValue = value
                            onFadeDurationChanged(value)
                        }
                        settingSlider(title: "Restore delay", value: restoreDelayValue, range: 0...0.30, suffix: "s") { value in
                            restoreDelayValue = value
                            onRestoreDelayChanged(value)
                        }
                    }
                    .padding(8)
                }
            }
        case .exceptions:
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if let currentApplicationName {
                        Text(currentApplicationName)
                            .font(.headline)
                        Text(currentApplicationIsExcluded ? "This app is excluded from dimming." : "This app is currently included in focus mode.")
                            .foregroundStyle(.secondary)
                        Button(currentApplicationIsExcluded ? "Include App" : "Exclude App", action: onToggleExclusion)
                    } else {
                        Text("No active application")
                            .foregroundStyle(.secondary)
                    }
                    Text("You can also manage the current app from the menu bar panel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        case .advanced:
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Accessibility") {
                    HStack {
                        Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityTrusted ? .green : .orange)
                        Text(accessibilityTrusted ? "Permission granted" : "Permission required for precise window tracking")
                        Spacer()
                        Button("Open System Settings", action: onOpenAccessibilitySettings)
                    }
                    .padding(8)
                }
                Text("Forelight keeps this permission at the app identity level, so rebuilding the app does not require adding it again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        suffix: String,
        action: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: Binding(get: { value }, set: { newValue in action(newValue) }), in: range)
            Text(String(format: "%.2f%@", value, suffix))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct IntensityControl: View {
    let value: Double
    let onChanged: (Double) -> Void

    @State private var sliderValue: Double
    @State private var textValue: String
    @FocusState private var textFieldFocused: Bool

    init(value: Double, onChanged: @escaping (Double) -> Void) {
        self.value = value
        self.onChanged = onChanged
        _sliderValue = State(initialValue: value)
        _textValue = State(initialValue: Self.displayValue(for: value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Dim intensity")
                Spacer()
                HStack(spacing: 3) {
                    TextField("45", text: Binding(
                        get: { textValue },
                        set: { textValue = $0.filter(\.isNumber) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($textFieldFocused)
                    .onSubmit(commitTextValue)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }

            Slider(value: $sliderValue, in: 0.10...0.90)
                .accessibilityLabel("Dim intensity")
                .onChange(of: sliderValue) { newValue in
                    textValue = Self.displayValue(for: newValue)
                    onChanged(newValue)
                }
        }
        .onChange(of: value) { newValue in
            guard !textFieldFocused else { return }
            sliderValue = newValue
            textValue = Self.displayValue(for: newValue)
        }
        .onChange(of: textFieldFocused) { focused in
            if !focused {
                commitTextValue()
            }
        }
    }

    private func commitTextValue() {
        let enteredValue = Int(textValue) ?? Int((sliderValue * 100).rounded())
        let percentage = min(max(enteredValue, 10), 90)
        let normalizedValue = Double(percentage) / 100
        sliderValue = normalizedValue
        textValue = String(percentage)
        onChanged(normalizedValue)
    }

    private static func displayValue(for value: Double) -> String {
        String(Int((value * 100).rounded()))
    }
}
