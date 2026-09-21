import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RuleEditorView: View {
    @State private var draft: Rule
    let groupNames: [String]
    let onSave: (Rule) -> Void
    let onCancel: () -> Void

    init(
        rule: Rule,
        groupNames: [String],
        onSave: @escaping (Rule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: rule)
        self.groupNames = groupNames
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    actionSection
                    conditionsSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
        .background(ForelightStyle.windowBackground)
        .tint(ForelightStyle.accent)
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Name")
            TextField("Rule name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Action")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Do", selection: actionKindBinding) {
                        ForEach(RuleActionKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220, alignment: .leading)

                    actionParameter
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var actionParameter: some View {
        switch draft.action {
        case .intensity(let value):
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: { draft.action = .intensity($0) }), in: ForelightSettings.intensityRange)
                PercentageField(value: value, range: ForelightSettings.intensityRange) { draft.action = .intensity($0) }
                    .fixedSize()
            }
        case .group(let name):
            Picker("Group", selection: Binding(
                get: { name },
                set: { draft.action = .group($0) }
            )) {
                if groupNames.isEmpty {
                    Text("No groups yet").tag("")
                }
                ForEach(groupNames, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220, alignment: .leading)
        case .snooze(let minutes):
            HStack(spacing: 8) {
                Stepper(value: Binding(
                    get: { minutes },
                    set: { draft.action = .snooze(minutes: max(1, $0)) }
                ), in: 1...240, step: 5) {
                    Text("\(minutes) minutes")
                }
            }
        case .spotlight(let mode):
            Picker("Spotlight", selection: Binding(
                get: { mode },
                set: { draft.action = .spotlight($0) }
            )) {
                ForEach(SpotlightMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220, alignment: .leading)
        case .enable, .disable:
            EmptyView()
        }
    }

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Conditions")
            Text("A rule runs when every condition below matches. Leave a condition on “Any” to ignore it.")
                .font(.caption)
                .foregroundStyle(ForelightStyle.muted)

            Card {
                appCondition
                CardDivider()
                timeCondition
                CardDivider()
                powerCondition
                CardDivider()
                displayCondition
                CardDivider()
                idleCondition
                CardDivider()
                microphoneCondition
            }
        }
    }

    // MARK: - Conditions

    private var appCondition: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Frontmost app")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { draft.frontmostApps != nil },
                    set: { draft.frontmostApps = $0 ? (draft.frontmostApps ?? []) : nil }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if let apps = draft.frontmostApps {
                if apps.isEmpty {
                    Text("Any app (add apps to narrow it)")
                        .font(.caption)
                        .foregroundStyle(ForelightStyle.muted)
                } else {
                    ForEach(apps, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            let info = AppInfoResolver.resolve(bundleID: bundleID)
                            if let icon = info.icon {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(info.name)
                            Spacer()
                            Button {
                                draft.frontmostApps?.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add Apps…", action: addApps)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var timeCondition: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Time window")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { draft.timeWindow != nil },
                    set: { enabled in
                        draft.timeWindow = enabled ? TimeWindow(days: [2, 3, 4, 5, 6], startMinutes: 9 * 60, endMinutes: 18 * 60) : nil
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if let window = draft.timeWindow {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let isOn = window.days.contains(day)
                        Button(TimeWindow.weekdayLabels[day - 1]) {
                            var days = draft.timeWindow?.days ?? []
                            if let index = days.firstIndex(of: day) {
                                days.remove(at: index)
                            } else {
                                days.append(day)
                            }
                            draft.timeWindow?.days = days.sorted()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(isOn ? ForelightStyle.accent : nil)
                    }
                }

                HStack(spacing: 10) {
                    DatePicker("From", selection: timeBinding(window.startMinutes) { draft.timeWindow?.startMinutes = $0 }, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: timeBinding(window.endMinutes) { draft.timeWindow?.endMinutes = $0 }, displayedComponents: .hourAndMinute)
                }
                .labelsHidden()
            }
        }
        .padding(12)
    }

    private var powerCondition: some View {
        HStack {
            Text("Power source")
            Spacer()
            Picker("", selection: Binding(
                get: { draft.powerSource },
                set: { draft.powerSource = $0 }
            )) {
                Text("Any").tag(PowerSource?.none)
                ForEach(PowerSource.allCases) { source in
                    Text(source.label).tag(PowerSource?.some(source))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(12)
    }

    private var displayCondition: some View {
        HStack {
            Text("External display")
            Spacer()
            Picker("", selection: Binding(
                get: { draft.externalDisplay },
                set: { draft.externalDisplay = $0 }
            )) {
                Text("Any").tag(Bool?.none)
                Text("Connected").tag(Bool?.some(true))
                Text("Not connected").tag(Bool?.some(false))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(12)
    }

    private var idleCondition: some View {
        HStack {
            Text("Idle for at least")
            Spacer()
            if let minutes = draft.idleMinutes {
                Stepper(value: Binding(
                    get: { minutes },
                    set: { draft.idleMinutes = max(1, $0) }
                ), in: 1...240, step: 1) {
                    Text("\(minutes) min")
                }
                Button {
                    draft.idleMinutes = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
            } else {
                Button("Any") { draft.idleMinutes = 5 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var microphoneCondition: some View {
        HStack {
            Text("Microphone in use")
            Spacer()
            Picker("", selection: Binding(
                get: { draft.microphoneInUse },
                set: { draft.microphoneInUse = $0 }
            )) {
                Text("Any").tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private var actionKindBinding: Binding<RuleActionKind> {
        Binding(
            get: { draft.action.kind },
            set: { draft.action = Self.defaultAction(for: $0, current: draft.action, groupNames: groupNames) }
        )
    }

    private static func defaultAction(for kind: RuleActionKind, current: RuleAction, groupNames: [String]) -> RuleAction {
        switch kind {
        case .enable: return .enable
        case .disable: return .disable
        case .intensity:
            if case .intensity(let value) = current { return .intensity(value) }
            return .intensity(0.45)
        case .group:
            if case .group(let name) = current { return .group(name) }
            return .group(groupNames.first ?? "")
        case .snooze:
            if case .snooze(let minutes) = current { return .snooze(minutes: minutes) }
            return .snooze(minutes: 30)
        case .spotlight:
            if case .spotlight(let mode) = current { return .spotlight(mode) }
            return .spotlight(.window)
        }
    }

    private func timeBinding(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = (minutes / 60) % 24
                components.minute = minutes % 60
                return calendar.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var apps = draft.frontmostApps ?? []
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier, !apps.contains(bundleID) {
                apps.append(bundleID)
            }
        }
        draft.frontmostApps = apps
    }
}
