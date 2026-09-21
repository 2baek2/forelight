import AppKit
import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: ForelightModel
    let onToggleEnabled: (Bool) -> Void
    let onIntensityChanged: (Double) -> Void
    let onToggleMoving: (Bool) -> Void
    let onToggleExclusion: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forelight")
                        .font(.headline)
                    Text(model.isEnabled ? "Focus mode is on" : "Focus mode is paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.isEnabled },
                    set: { value in onToggleEnabled(value) }
                ))
                    .labelsHidden()
            }

            Divider()

            IntensityControl(value: model.intensity, onChanged: onIntensityChanged)

            Toggle("Hide while moving a window", isOn: Binding(
                get: { model.hideWhileMoving },
                set: { value in onToggleMoving(value) }
            ))

            if let currentApplicationName = model.currentApplicationName {
                Button(action: onToggleExclusion) {
                    Label(
                        model.currentApplicationIsExcluded ? "Include " + currentApplicationName : "Exclude " + currentApplicationName,
                        systemImage: model.currentApplicationIsExcluded ? "eye" : "eye.slash"
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
    enum Section: String, CaseIterable, Identifiable {
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

    @ObservedObject var model: ForelightModel
    let onToggleEnabled: (Bool) -> Void
    let onIntensityChanged: (Double) -> Void
    let onToggleMoving: (Bool) -> Void
    let onFadeDurationChanged: (Double) -> Void
    let onRestoreDelayChanged: (Double) -> Void
    let onSetException: (String, Bool) -> Void
    let onRemoveException: (String) -> Void
    let onAddException: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    @State private var selectedSection: Section = .general
    @State private var selectedExceptionID: String?

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
                        get: { model.isEnabled },
                        set: { value in onToggleEnabled(value) }
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
                        IntensityControl(value: model.intensity, onChanged: onIntensityChanged)
                        Toggle("Hide while moving a window", isOn: Binding(
                            get: { model.hideWhileMoving },
                            set: { value in onToggleMoving(value) }
                        ))
                    }
                    .padding(8)
                }
                GroupBox("Window movement") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingSlider(title: "Fade animation", value: model.fadeDuration, range: 0...0.35, suffix: "s") { value in
                            onFadeDurationChanged(value)
                        }
                        settingSlider(title: "Restore delay", value: model.restoreDelay, range: 0...0.30, suffix: "s") { value in
                            onRestoreDelayChanged(value)
                        }
                    }
                    .padding(8)
                }
            }
        case .exceptions:
            VStack(alignment: .leading, spacing: 12) {
                Text("Apps listed here are excluded from dimming. Toggle an app off to keep it in the list without excluding it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if model.exceptions.isEmpty {
                    Text("No apps are excluded yet. Use + to add one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    List(selection: $selectedExceptionID) {
                        ForEach(model.exceptions) { entry in
                            HStack(spacing: 10) {
                                if let icon = entry.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "app.dashed")
                                        .frame(width: 20, height: 20)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.name)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { entry.isEnabled },
                                    set: { value in onSetException(entry.bundleID, value) }
                                ))
                                    .labelsHidden()
                            }
                            .tag(entry.bundleID)
                        }
                    }
                    .frame(minHeight: 220)
                }

                HStack(spacing: 6) {
                    Button(action: onAddException) {
                        Image(systemName: "plus")
                    }
                    .help("Add an application")

                    Button {
                        guard let selectedExceptionID else { return }
                        onRemoveException(selectedExceptionID)
                        self.selectedExceptionID = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedExceptionID == nil)
                    .help("Remove the selected application")

                    Spacer()
                }
                .buttonStyle(.borderless)
            }
        case .advanced:
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Accessibility") {
                    HStack {
                        Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                        Text(model.accessibilityTrusted ? "Permission granted" : "Permission required for precise window tracking")
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
