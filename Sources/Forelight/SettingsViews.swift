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
        VStack(alignment: .leading, spacing: 12) {
            header

            Card {
                IntensityControl(value: model.intensity, onChanged: onIntensityChanged)
                    .padding(12)
            }

            Card {
                CardRow(
                    title: "Hide while moving",
                    subtitle: "Clear dimming while dragging",
                    systemImage: "hand.draw"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.hideWhileMoving },
                        set: { value in onToggleMoving(value) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if let currentApplicationName = model.currentApplicationName {
                Card {
                    CardRow(
                        title: currentApplicationName,
                        subtitle: model.currentApplicationIsExcluded ? "Excluded from dimming" : "Included in dimming",
                        systemImage: "app"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { model.currentApplicationIsExcluded },
                            set: { _ in onToggleExclusion() }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Settings…", action: onOpenSettings)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 330)
        .tint(ForelightStyle.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ForelightStyle.accentSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: "viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ForelightStyle.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Forelight")
                    .font(.headline)
                StatusPill(
                    text: model.isEnabled ? "Focus mode on" : "Focus mode paused",
                    color: model.isEnabled ? ForelightStyle.green : .secondary
                )
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.isEnabled },
                set: { value in onToggleEnabled(value) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
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

        var subtitle: String {
            switch self {
            case .general: return "Turn dimming on or off and check the global shortcut."
            case .focus: return "Control how much the background is dimmed and how window movement is handled."
            case .exceptions: return "Apps that stay clear while everything else is dimmed."
            case .advanced: return "Permissions and deeper behavior."
            }
        }
    }

    @ObservedObject var model: ForelightModel
    let onToggleEnabled: (Bool) -> Void
    let onIntensityChanged: (Double) -> Void
    let onToggleMoving: (Bool) -> Void
    let onFadeDurationChanged: (Double) -> Void
    let onRestoreDelayChanged: (Double) -> Void
    let onAppearanceModeChanged: (AppearanceMode) -> Void
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
                    .padding(.vertical, 4)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 38)
            .frame(width: 200)
            .frame(maxHeight: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedSection.rawValue)
                            .font(.title2.weight(.semibold))
                        Text(selectedSection.subtitle)
                            .font(.callout)
                            .foregroundStyle(ForelightStyle.muted)
                    }
                    detailView
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .tint(ForelightStyle.accent)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            Card {
                CardRow(
                    title: "Enable Forelight",
                    subtitle: "Dim everything except the front window",
                    systemImage: "viewfinder"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.isEnabled },
                        set: { value in onToggleEnabled(value) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                CardDivider()
                CardRow(
                    title: "Toggle focus mode",
                    subtitle: "Works from any app",
                    systemImage: "keyboard"
                ) {
                    Text("⌥⌘F")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(ForelightStyle.muted)
                }
                CardDivider()
                CardRow(
                    title: "Appearance",
                    subtitle: "Follow the system or force a mode",
                    systemImage: "circle.lefthalf.filled"
                ) {
                    Picker("", selection: Binding(
                        get: { model.appearanceMode },
                        set: { mode in onAppearanceModeChanged(mode) }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
            }
        case .focus:
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    IntensityControl(value: model.intensity, onChanged: onIntensityChanged)
                        .padding(12)
                    CardDivider()
                    CardRow(
                        title: "Hide while moving",
                        subtitle: "Clear the dimming while a window is dragged",
                        systemImage: "hand.draw"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { model.hideWhileMoving },
                            set: { value in onToggleMoving(value) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Window movement")
                    Card {
                        SliderRow(
                            title: "Fade animation",
                            value: model.fadeDuration,
                            range: 0...0.35,
                            suffix: "s",
                            onChanged: onFadeDurationChanged
                        )
                        CardDivider()
                        SliderRow(
                            title: "Restore delay",
                            value: model.restoreDelay,
                            range: 0...0.30,
                            suffix: "s",
                            onChanged: onRestoreDelayChanged
                        )
                    }
                }
            }
        case .exceptions:
            VStack(alignment: .leading, spacing: 12) {
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
                                    .foregroundStyle(ForelightStyle.muted)
                            }
                            Text(entry.name)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { entry.isEnabled },
                                set: { value in onSetException(entry.bundleID, value) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                        .tag(entry.bundleID)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(ForelightStyle.cardBackground)
                .frame(minHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: ForelightStyle.cardCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ForelightStyle.cardCorner, style: .continuous)
                        .strokeBorder(ForelightStyle.cardBorder, lineWidth: 1)
                )
                .overlay {
                    if model.exceptions.isEmpty {
                        Text("No apps are excluded yet. Use + to add one.")
                            .foregroundStyle(ForelightStyle.muted)
                    }
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
                .controlSize(.small)
            }
        case .advanced:
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    HStack(spacing: 10) {
                        Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.accessibilityTrusted ? ForelightStyle.green : ForelightStyle.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility")
                            Text(model.accessibilityTrusted ? "Permission granted" : "Required for precise window tracking")
                                .font(.caption)
                                .foregroundStyle(ForelightStyle.muted)
                        }
                        Spacer()
                        Button("Open System Settings", action: onOpenAccessibilitySettings)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)
                }
                Text("Forelight keeps this permission at the app identity level, so rebuilding the app does not require adding it again.")
                    .font(.callout)
                    .foregroundStyle(ForelightStyle.muted)
            }
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
                        .foregroundStyle(ForelightStyle.muted)
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
