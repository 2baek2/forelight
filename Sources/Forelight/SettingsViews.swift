import AppKit
import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: ForelightModel
    let onToggleEnabled: (Bool) -> Void
    let onIntensityChanged: (Double) -> Void
    let onToggleMoving: (Bool) -> Void
    let onToggleExclusion: () -> Void
    let onToggleAppIntensityOverride: () -> Void
    let onAppearanceModeChanged: (AppearanceMode) -> Void
    let onSnooze: (Int) -> Void
    let onCancelSnooze: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    IntensityControl(value: model.effectiveIntensity, onChanged: onIntensityChanged)

                    HStack(spacing: 6) {
                        Text(intensityContextLabel)
                            .font(.caption)
                            .foregroundStyle(ForelightStyle.muted)
                        Spacer()
                        if model.currentApplicationName != nil {
                            Button(model.currentApplicationHasIntensityOverride ? "Use default" : "Customize") {
                                onToggleAppIntensityOverride()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
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

            Card {
                CardRow(
                    title: "Snooze",
                    subtitle: snoozeSubtitle,
                    systemImage: "moon.zzz"
                ) {
                    Menu(model.isSnoozed ? "Paused" : "Snooze") {
                        Button("15 minutes") { onSnooze(15) }
                        Button("30 minutes") { onSnooze(30) }
                        Button("1 hour") { onSnooze(60) }
                        Divider()
                        Button("Resume now") { onCancelSnooze() }
                            .disabled(!model.isSnoozed)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 96)
                }
            }

            Card {
                CardRow(
                    title: "Appearance",
                    subtitle: "System, light, dark",
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
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 118)
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

    private var intensityContextLabel: String {
        if model.currentApplicationHasIntensityOverride, let name = model.currentApplicationName {
            return "Custom for \(name)"
        }
        return "All apps"
    }

    private var snoozeSubtitle: String {
        guard let until = model.snoozeUntil else { return "Temporarily pause dimming" }
        return "Paused until \(Self.snoozeTimeFormatter.string(from: until))"
    }

    private static let snoozeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case focus = "Focus"
        case exceptions = "Exceptions"
        case apps = "Apps"
        case displays = "Displays"
        case groups = "Groups"
        case advanced = "Advanced"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .focus: return "viewfinder"
            case .exceptions: return "eye.slash"
            case .apps: return "square.grid.2x2"
            case .displays: return "display"
            case .groups: return "square.stack.3d.up"
            case .advanced: return "gearshape"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Turn dimming on or off and check the global shortcut."
            case .focus: return "Control how much the background is dimmed and how window movement is handled."
            case .exceptions: return "Apps that stay clear while everything else is dimmed."
            case .apps: return "Give individual apps their own dim intensity."
            case .displays: return "Give each screen its own dim intensity."
            case .groups: return "Save the current setup as a group and switch between them."
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
    let onShortcutChanged: (KeyCombo) -> Void
    let onShortcutRecordingChanged: (Bool) -> Void
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onSetException: (String, Bool) -> Void
    let onRemoveException: (String) -> Void
    let onAddException: () -> Void
    let onSetAppIntensity: (String, Double) -> Void
    let onSetAppIntensityEnabled: (String, Bool) -> Void
    let onRemoveAppIntensity: (String) -> Void
    let onAddAppIntensity: () -> Void
    let onSetDisplayIntensity: (String, Double) -> Void
    let onSetDisplayDimmingEnabled: (String, Bool) -> Void
    let onRemoveDisplayIntensity: (String) -> Void
    let onApplyGroup: (String) -> Void
    let onSaveGroup: () -> Void
    let onDeleteGroup: (String) -> Void
    let onExportSettings: () -> Void
    let onImportSettings: () -> Void
    let onResetSettings: () -> Void
    let onShowOnboarding: () -> Void
    let onShowAbout: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    @State private var selectedSection: Section = .general
    @State private var selectedExceptionID: String?
    @State private var selectedAppIntensityID: String?
    @State private var selectedDisplayID: String?
    @State private var selectedGroupName: String?

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
                    subtitle: "Click, then press a new shortcut",
                    systemImage: "keyboard"
                ) {
                    HStack(spacing: 6) {
                        ShortcutRecorder(
                            combo: model.shortcut,
                            onChange: { combo in onShortcutChanged(combo) },
                            onRecordingChanged: { recording in onShortcutRecordingChanged(recording) }
                        )
                        .frame(width: 140, height: 24)

                        Button("Reset") {
                            onShortcutChanged(.default)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
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
                CardDivider()
                CardRow(
                    title: "Launch at login",
                    subtitle: "Start Forelight when you sign in",
                    systemImage: "power"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { value in onLaunchAtLoginChanged(value) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
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
        case .apps:
            VStack(alignment: .leading, spacing: 12) {
                List(selection: $selectedAppIntensityID) {
                    ForEach(model.appIntensityOverrides) { entry in
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
                                set: { value in onSetAppIntensityEnabled(entry.bundleID, value) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            Slider(
                                value: Binding(
                                    get: { entry.value },
                                    set: { value in onSetAppIntensity(entry.bundleID, value) }
                                ),
                                in: ForelightSettings.intensityRange
                            )
                            .frame(width: 150)
                            .disabled(!entry.isEnabled)
                            Text("\(Int((entry.value * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ForelightStyle.muted)
                                .frame(width: 42, alignment: .trailing)
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
                    if model.appIntensityOverrides.isEmpty {
                        Text("No custom intensities yet. Use + to add an app.")
                            .foregroundStyle(ForelightStyle.muted)
                    }
                }

                HStack(spacing: 6) {
                    Button(action: onAddAppIntensity) {
                        Image(systemName: "plus")
                    }
                    .help("Add an application")

                    Button {
                        guard let selectedAppIntensityID else { return }
                        onRemoveAppIntensity(selectedAppIntensityID)
                        self.selectedAppIntensityID = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedAppIntensityID == nil)
                    .help("Remove the selected application")

                    Spacer()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        case .displays:
            VStack(alignment: .leading, spacing: 12) {
                List(selection: $selectedDisplayID) {
                    ForEach(model.displays) { display in
                        HStack(spacing: 10) {
                            Image(systemName: display.isDimmingEnabled ? "display" : "display.slash")
                                .foregroundStyle(display.isDimmingEnabled ? ForelightStyle.muted2 : ForelightStyle.muted)
                                .frame(width: 20)
                            Text(display.name)
                            if display.hasOverride {
                                Text("Custom")
                                    .font(.caption)
                                    .foregroundStyle(ForelightStyle.muted)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { display.isDimmingEnabled },
                                set: { value in onSetDisplayDimmingEnabled(display.id, value) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            Slider(
                                value: Binding(
                                    get: { display.value },
                                    set: { value in onSetDisplayIntensity(display.id, value) }
                                ),
                                in: ForelightSettings.intensityRange
                            )
                            .frame(width: 150)
                            .disabled(!display.isDimmingEnabled)
                            Text("\(Int((display.value * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ForelightStyle.muted)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                        .tag(display.id)
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
                    if model.displays.isEmpty {
                        Text("No displays detected.")
                            .foregroundStyle(ForelightStyle.muted)
                    }
                }

                HStack(spacing: 6) {
                    Button {
                        guard let selectedDisplayID else { return }
                        onRemoveDisplayIntensity(selectedDisplayID)
                        self.selectedDisplayID = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedDisplayID == nil)
                    .help("Clear the custom intensity for the selected display")

                    Spacer()

                    Text("Turn a switch off to skip that display. A display override wins over an app override.")
                        .font(.caption)
                        .foregroundStyle(ForelightStyle.muted)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        case .groups:
            VStack(alignment: .leading, spacing: 12) {
                List(selection: $selectedGroupName) {
                    ForEach(model.focusGroups) { group in
                        HStack(spacing: 10) {
                            Image(systemName: model.activeGroupName == group.name ? "checkmark.circle.fill" : "square.stack.3d.up")
                                .foregroundStyle(model.activeGroupName == group.name ? ForelightStyle.green : ForelightStyle.muted2)
                                .frame(width: 20)
                            Text(group.name)
                            Spacer()
                            Button("Apply") { onApplyGroup(group.name) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                        .tag(group.name)
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
                    if model.focusGroups.isEmpty {
                        Text("No groups yet. Use + to save the current setup.")
                            .foregroundStyle(ForelightStyle.muted)
                    }
                }

                HStack(spacing: 6) {
                    Button(action: onSaveGroup) {
                        Image(systemName: "plus")
                    }
                    .help("Save the current setup as a group")

                    Button {
                        guard let selectedGroupName else { return }
                        onDeleteGroup(selectedGroupName)
                        self.selectedGroupName = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedGroupName == nil)
                    .help("Remove the selected group")

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

                Card {
                    CardRow(title: "Setup", subtitle: "Revisit permissions and the shortcut", systemImage: "sparkles") {
                        Button("Show Welcome", action: onShowOnboarding)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    CardDivider()
                    CardRow(title: "About", subtitle: "Version and credits", systemImage: "info.circle") {
                        Button("About Forelight", action: onShowAbout)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Card {
                    CardRow(title: "Export Settings", subtitle: "Save everything to a JSON file", systemImage: "square.and.arrow.up") {
                        Button("Export…", action: onExportSettings)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    CardDivider()
                    CardRow(title: "Import Settings", subtitle: "Restore from a JSON file", systemImage: "square.and.arrow.down") {
                        Button("Import…", action: onImportSettings)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    CardDivider()
                    CardRow(title: "Reset Settings", subtitle: "Clear exceptions, apps, groups and preferences", systemImage: "trash") {
                        Button("Reset…", action: onResetSettings)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
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
