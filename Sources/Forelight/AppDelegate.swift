import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let overlayController: OverlayController
    private let model: ForelightModel
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var settingsHostingController: NSHostingController<SettingsView>?
    private var aboutWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var ruleEditorWindow: NSWindow?
    private var enabled: Bool
    private var appearanceMode: AppearanceMode
    private var shortcut: KeyCombo
    private var autoCheckForUpdates: Bool
    private var isCheckingForUpdates = false
    private var availableUpdateVersion: String?
    private let shortcutGate = ShortcutGate()
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var keyboardMonitors: [Any] = []

    override init() {
        let controller = OverlayController()
        overlayController = controller
        enabled = UserDefaults.standard.object(forKey: ForelightSettings.enabledKey) as? Bool ?? true
        appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: ForelightSettings.appearanceModeKey) ?? ""
        ) ?? .dark
        if let data = UserDefaults.standard.data(forKey: ForelightSettings.shortcutKey),
           let savedShortcut = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            shortcut = savedShortcut
        } else {
            shortcut = .default
        }
        autoCheckForUpdates = UserDefaults.standard.object(forKey: ForelightSettings.autoCheckForUpdatesKey) as? Bool ?? true
        model = ForelightModel(
            isEnabled: enabled,
            currentApplicationName: nil,
            currentApplicationIsExcluded: false,
            accessibilityTrusted: false,
            intensity: controller.intensity,
            hideWhileMoving: controller.hideWhileMoving,
            fadeDuration: controller.fadeDuration,
            restoreDelay: controller.restoreDelay,
            exceptions: [],
            appearanceMode: appearanceMode,
            shortcut: shortcut,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            effectiveIntensity: controller.displayedIntensity,
            currentApplicationHasIntensityOverride: false,
            appIntensityOverrides: [],
            isSnoozed: false,
            snoozeUntil: nil,
            focusGroups: [],
            activeGroupName: nil,
            displays: [],
            spotlightMode: controller.spotlightMode,
            spotlightRadius: controller.spotlightRadius,
            spotlightFeather: controller.spotlightFeather,
            cutoutRadius: controller.cutoutRadius,
            cutoutPadding: controller.cutoutPadding,
            tintRed: controller.tintRed,
            tintGreen: controller.tintGreen,
            tintBlue: controller.tintBlue,
            cutoutAllWindows: controller.cutoutAllWindows,
            cutoutAnimationDuration: controller.cutoutAnimationDuration,
            vignetteStrength: controller.vignetteStrength,
            rules: controller.rules,
            activeRuleID: nil,
            isCheckingForUpdates: false,
            availableUpdateVersion: nil,
            autoCheckForUpdates: autoCheckForUpdates
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureNotifications()
        configureGlobalShortcut()
        configureURLEvents()
        overlayController.onRuleAction = { [weak self] action in
            self?.applyRuleAction(action)
        }
        overlayController.start()
        overlayController.setEnabled(enabled)
        refreshUI()
        showOnboardingIfNeeded()
        scheduleAutomaticUpdateCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
        keyboardMonitors.forEach { NSEvent.removeMonitor($0) }
        keyboardMonitors.removeAll()
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        overlayController.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = appearanceMode.nsAppearance
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView(
                model: model,
                onToggleEnabled: { [weak self] value in self?.setEnabled(value) },
                onIntensityChanged: { [weak self] value in self?.setDisplayedIntensity(value) },
                onToggleMoving: { [weak self] value in self?.setHideWhileMoving(value) },
                onToggleExclusion: { [weak self] in self?.toggleCurrentApplicationExclusion() },
                onToggleAppIntensityOverride: { [weak self] in self?.toggleCurrentApplicationIntensityOverride() },
                onAppearanceModeChanged: { [weak self] mode in self?.setAppearanceMode(mode) },
                onSnooze: { [weak self] minutes in self?.snooze(forMinutes: minutes) },
                onCancelSnooze: { [weak self] in self?.cancelSnooze() },
                onOpenSettings: { [weak self] in self?.presentSettings() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
    }

    private func configureNotifications() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.overlayController.refreshFrontmostApplication()
                self?.refreshUI()
            }
        }

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.overlayController.refreshFrontmostApplication()
                self?.refreshUI()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivationChanged),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivationChanged),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private enum ShortcutAction: Sendable {
        case toggle
        case group(String)
    }

    private func configureGlobalShortcut() {
        keyboardMonitors.forEach { NSEvent.removeMonitor($0) }
        keyboardMonitors.removeAll()

        // Capture the bindings by value so the check happens against the combos
        // that were current when the event arrived, not a later edit.
        var bindings: [(combo: KeyCombo, action: ShortcutAction)] = [(shortcut, .toggle)]
        for group in overlayController.focusGroups {
            if let combo = group.shortcut {
                bindings.append((combo, .group(group.name)))
            }
        }

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard !event.isARepeat, self?.shortcutGate.isSuppressed != true else { return }
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            guard let binding = bindings.first(where: {
                $0.combo.keyCode == keyCode && $0.combo.modifiers == modifiers
            }) else {
                return
            }
            let action = binding.action
            Task { @MainActor [weak self] in
                switch action {
                case .toggle:
                    self?.toggleEnabled()
                case .group(let name):
                    self?.applyGroup(named: name)
                }
            }
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            keyboardMonitors.append(globalMonitor)
        }
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            keyboardMonitors.append(localMonitor)
        }
    }

    private func configureURLEvents() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }
        handle(url: url)
    }

    private func handle(url: URL) {
        guard url.scheme?.lowercased() == "forelight" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            (components?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { _, latest in latest }
        )

        switch url.host?.lowercased() ?? "" {
        case "toggle":
            setEnabled(!enabled)
        case "enable":
            setEnabled(true)
        case "disable":
            setEnabled(false)
        case "snooze":
            snooze(forMinutes: Int(query["minutes"] ?? "") ?? 30)
        case "resume":
            cancelSnooze()
        case "intensity":
            if let value = Double(query["value"] ?? "") {
                setIntensity(value)
            }
        case "appearance":
            if let raw = query["mode"], let mode = AppearanceMode(rawValue: raw.lowercased()) {
                setAppearanceMode(mode)
            }
        case "group":
            if let name = query["name"] {
                applyGroup(named: name)
            }
        case "spotlight":
            if let raw = query["mode"], let mode = spotlightMode(from: raw) {
                setSpotlightMode(mode)
            }
        default:
            break
        }
    }

    private func spotlightMode(from value: String) -> SpotlightMode? {
        switch value.lowercased() {
        case "window", "off", "none":
            return .window
        case "cursor", "spotlight":
            return .cursor
        case "both", "window+cursor", "windowandcursor":
            return .windowAndCursor
        default:
            return nil
        }
    }

    @objc private func screenParametersChanged() {
        overlayController.rebuildOverlays()
        refreshUI()
    }

    @objc private func applicationActivationChanged() {
        // Keep the settings window above the dim overlay only while Forelight is
        // the active app; otherwise behave like a normal window and go behind
        // whatever the user is actually working in.
        settingsWindow?.level = NSApp.isActive ? .modalPanel : .normal
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func presentStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: enabled ? "Disable Forelight" : "Enable Forelight",
            action: #selector(toggleEnabledFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let snoozeItem = NSMenuItem(title: "Snooze", action: nil, keyEquivalent: "")
        let snoozeMenu = NSMenu()
        for (title, minutes) in [("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60)] {
            let item = NSMenuItem(title: title, action: #selector(snoozeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            snoozeMenu.addItem(item)
        }
        snoozeMenu.addItem(.separator())
        let resumeItem = NSMenuItem(title: "Resume now", action: #selector(cancelSnoozeFromMenu), keyEquivalent: "")
        resumeItem.target = self
        resumeItem.isEnabled = overlayController.isSnoozed
        snoozeMenu.addItem(resumeItem)
        snoozeItem.submenu = snoozeMenu
        menu.addItem(snoozeItem)
        menu.addItem(.separator())

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for mode in AppearanceMode.allCases {
            let item = NSMenuItem(
                title: mode.label,
                action: #selector(setAppearanceFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = appearanceMode == mode ? .on : .off
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        menu.addItem(.separator())

        let spotlightItem = NSMenuItem(title: "Cursor Spotlight", action: nil, keyEquivalent: "")
        let spotlightMenu = NSMenu()
        for mode in SpotlightMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setSpotlightFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = overlayController.spotlightMode == mode ? .on : .off
            spotlightMenu.addItem(item)
        }
        spotlightItem.submenu = spotlightMenu
        menu.addItem(spotlightItem)
        menu.addItem(.separator())

        let groupsItem = NSMenuItem(title: "Focus Groups", action: nil, keyEquivalent: "")
        let groupsMenu = NSMenu()
        for group in overlayController.focusGroups {
            let item = NSMenuItem(title: group.name, action: #selector(applyGroupFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = group.name
            item.state = overlayController.activeGroupName == group.name ? .on : .off
            groupsMenu.addItem(item)
        }
        if !overlayController.focusGroups.isEmpty {
            groupsMenu.addItem(.separator())
        }
        let saveGroupItem = NSMenuItem(title: "Save Current…", action: #selector(saveGroupFromMenu), keyEquivalent: "")
        saveGroupItem.target = self
        groupsMenu.addItem(saveGroupItem)
        groupsItem.submenu = groupsMenu
        menu.addItem(groupsItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Forelight", action: #selector(showAboutFromMenu), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let setupItem = NSMenuItem(title: "Setup…", action: #selector(showOnboardingFromMenu), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let supportItem = NSMenuItem(title: "Support Forelight…", action: #selector(openSupportFromMenu), keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Forelight",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 6),
            in: button
        )
    }

    @objc private func toggleEnabledFromMenu() {
        toggleEnabled()
    }

    @objc private func openSettingsFromMenu() {
        presentSettings()
    }

    @objc private func setAppearanceFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AppearanceMode(rawValue: raw) else { return }
        setAppearanceMode(mode)
    }

    @objc private func setSpotlightFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SpotlightMode(rawValue: raw) else { return }
        setSpotlightMode(mode)
    }

    @objc private func snoozeFromMenu(_ sender: NSMenuItem) {
        snooze(forMinutes: sender.tag)
    }

    @objc private func cancelSnoozeFromMenu() {
        cancelSnooze()
    }

    @objc private func applyGroupFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        applyGroup(named: name)
    }

    @objc private func saveGroupFromMenu() {
        saveCurrentAsGroup()
    }

    @objc private func showAboutFromMenu() {
        showAbout()
    }

    @objc private func showOnboardingFromMenu() {
        showOnboarding()
    }

    @objc private func openSupportFromMenu() {
        NSWorkspace.shared.open(ForelightLinks.support)
    }

    @objc private func checkForUpdatesFromMenu() {
        checkForUpdates(userInitiated: true)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func refreshUI() {
        updateStatusItem()
        syncModel()
    }

    private func syncModel() {
        model.isEnabled = enabled
        model.currentApplicationName = overlayController.currentApplicationName
        model.currentApplicationIsExcluded = overlayController.currentApplicationIsExcluded
        model.accessibilityTrusted = overlayController.accessibilityTrusted
        model.intensity = overlayController.intensity
        model.hideWhileMoving = overlayController.hideWhileMoving
        model.fadeDuration = overlayController.fadeDuration
        model.restoreDelay = overlayController.restoreDelay
        model.appearanceMode = appearanceMode
        model.shortcut = shortcut
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.isSnoozed = overlayController.isSnoozed
        model.snoozeUntil = overlayController.snoozeUntilDate
        model.focusGroups = overlayController.focusGroups
        model.activeGroupName = overlayController.activeGroupName
        model.spotlightMode = overlayController.spotlightMode
        model.spotlightRadius = overlayController.spotlightRadius
        model.spotlightFeather = overlayController.spotlightFeather
        model.cutoutRadius = overlayController.cutoutRadius
        model.cutoutPadding = overlayController.cutoutPadding
        model.tintRed = overlayController.tintRed
        model.tintGreen = overlayController.tintGreen
        model.tintBlue = overlayController.tintBlue
        model.cutoutAllWindows = overlayController.cutoutAllWindows
        model.cutoutAnimationDuration = overlayController.cutoutAnimationDuration
        model.vignetteStrength = overlayController.vignetteStrength
        model.rules = overlayController.rules
        model.activeRuleID = overlayController.activeRuleID
        model.isCheckingForUpdates = isCheckingForUpdates
        model.availableUpdateVersion = availableUpdateVersion
        model.autoCheckForUpdates = autoCheckForUpdates
        model.displays = NSScreen.screens.compactMap { screen -> DisplayIntensityEntry? in
            guard let info = DisplayIdentifier.info(for: screen) else { return nil }
            return DisplayIntensityEntry(
                id: info.id,
                name: info.name,
                value: overlayController.displayIntensityValue(for: info.id),
                hasOverride: overlayController.displayIntensityStates[info.id] != nil,
                isDimmingEnabled: overlayController.isDisplayDimmingEnabled(info.id)
            )
        }
        model.effectiveIntensity = overlayController.displayedIntensity
        model.currentApplicationHasIntensityOverride = overlayController.currentApplicationHasIntensityOverride
        model.appIntensityOverrides = overlayController.appIntensityStates
            .map { bundleID, value in
                let info = AppInfoResolver.resolve(bundleID: bundleID)
                return AppIntensityEntry(
                    bundleID: bundleID,
                    name: info.name,
                    icon: info.icon,
                    value: value,
                    isEnabled: overlayController.isAppIntensityEnabled(bundleID)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        model.exceptions = overlayController.exceptionStates
            .map { bundleID, isEnabled in
                let info = AppInfoResolver.resolve(bundleID: bundleID)
                return ExceptionEntry(
                    bundleID: bundleID,
                    name: info.name,
                    icon: info.icon,
                    isEnabled: isEnabled
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updateStatusItem() {
        let symbol = enabled ? "viewfinder" : "viewfinder.circle"
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: enabled ? "Forelight enabled" : "Forelight disabled"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        let appName = overlayController.currentApplicationName ?? "No active app"
        statusItem.button?.toolTip = enabled ? "Forelight · " + appName : "Forelight paused"
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.enabledKey)
        overlayController.setEnabled(value)
        refreshUI()
    }

    private func snooze(forMinutes minutes: Int) {
        overlayController.snooze(until: Date().addingTimeInterval(TimeInterval(minutes) * 60))
        refreshUI()
    }

    private func cancelSnooze() {
        overlayController.cancelSnooze()
        refreshUI()
    }

    private func applyGroup(named name: String) {
        overlayController.applyGroup(named: name)
        refreshUI()
    }

    private func saveCurrentAsGroup() {
        guard let name = promptForGroupName() else { return }
        overlayController.saveCurrentAsGroup(named: name)
        configureGlobalShortcut()
        refreshUI()
    }

    private func deleteGroup(named name: String) {
        overlayController.deleteGroup(named: name)
        configureGlobalShortcut()
        refreshUI()
    }

    private func setGroupShortcut(groupName: String, combo: KeyCombo?) {
        overlayController.setGroupShortcut(groupName: groupName, combo: combo)
        configureGlobalShortcut()
        refreshUI()
    }

    private func setGroupShortcutRecording(_ recording: Bool) {
        shortcutGate.setSuppressed(recording)
    }

    // MARK: - Rules

    private func applyRuleAction(_ action: RuleAction) {
        switch action {
        case .enable:
            setEnabled(true)
        case .disable:
            setEnabled(false)
        case .intensity(let value):
            setIntensity(value)
        case .group(let name):
            applyGroup(named: name)
        case .snooze(let minutes):
            snooze(forMinutes: minutes)
        case .spotlight(let mode):
            setSpotlightMode(mode)
        }
        refreshUI()
    }

    private func addRule() {
        presentRuleEditor(rule: Rule(name: "New Rule"))
    }

    private func editRule(id: UUID) {
        guard let rule = overlayController.rules.first(where: { $0.id == id }) else { return }
        presentRuleEditor(rule: rule)
    }

    private func deleteRule(id: UUID) {
        overlayController.deleteRule(id: id)
        refreshUI()
    }

    private func setRuleEnabled(id: UUID, enabled: Bool) {
        overlayController.setRuleEnabled(id: id, enabled: enabled)
        refreshUI()
    }

    private func saveRule(_ rule: Rule) {
        overlayController.updateRule(rule)
        ruleEditorWindow?.close()
        ruleEditorWindow = nil
        refreshUI()
    }

    private func presentRuleEditor(rule: Rule) {
        if ruleEditorWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Rule"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            ruleEditorWindow = window
        }

        ruleEditorWindow?.contentViewController = NSHostingController(
            rootView: RuleEditorView(
                rule: rule,
                groupNames: overlayController.focusGroups.map(\.name),
                onSave: { [weak self] updated in self?.saveRule(updated) },
                onCancel: { [weak self] in
                    self?.ruleEditorWindow?.close()
                    self?.ruleEditorWindow = nil
                }
            )
        )
        presentAuxiliaryWindow(ruleEditorWindow)
    }

    private func promptForGroupName() -> String? {
        let alert = NSAlert()
        alert.messageText = "Save Focus Group"
        alert.informativeText = "Stores the current intensity, exceptions, and per-app intensities."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Group name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: - Settings import / export / reset

    private func exportSettings() {
        var document = SettingsDocument.load(from: .standard)
        document.launchAtLogin = SMAppService.mainApp.status == .enabled

        let panel = NSSavePanel()
        panel.title = "Export Forelight Settings"
        panel.nameFieldStringValue = "Forelight Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try document.encoded().write(to: url)
        } catch {
            presentSimpleAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Import Forelight Settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let document = try SettingsDocument.decode(from: data)
            if let launch = document.launchAtLogin, launch != (SMAppService.mainApp.status == .enabled) {
                setLaunchAtLogin(launch)
            }
            document.write(to: .standard)
            applyAfterSettingsChange()
        } catch {
            presentSimpleAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings?"
        alert.informativeText = "This clears your exceptions, per-app intensities, groups, appearance, and shortcut. It cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for key in ForelightSettings.allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        applyAfterSettingsChange()
    }

    private func applyAfterSettingsChange() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: ForelightSettings.enabledKey) as? Bool ?? true
        appearanceMode = AppearanceMode(
            rawValue: defaults.string(forKey: ForelightSettings.appearanceModeKey) ?? ""
        ) ?? .dark
        if let data = defaults.data(forKey: ForelightSettings.shortcutKey),
           let saved = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }

        overlayController.reloadFromDefaults()
        popover.appearance = appearanceMode.nsAppearance
        settingsWindow?.appearance = appearanceMode.nsAppearance
        settingsWindow?.backgroundColor = ForelightStyle.windowNSColor
        configureGlobalShortcut()
        overlayController.setEnabled(enabled)
        refreshUI()
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - About and onboarding

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    private static var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    // MARK: - Updates

    private func checkForUpdates(userInitiated: Bool) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        syncModel()

        Task { @MainActor in
            defer {
                isCheckingForUpdates = false
                UserDefaults.standard.set(Date(), forKey: ForelightSettings.lastUpdateCheckKey)
                syncModel()
            }

            do {
                let release = try await UpdateChecker.latestRelease()
                if UpdateChecker.isNewer(release.version, than: Self.appShortVersion) {
                    availableUpdateVersion = release.version
                    let offered = UserDefaults.standard.string(forKey: ForelightSettings.offeredUpdateVersionKey)
                    if userInitiated || offered != release.version {
                        UserDefaults.standard.set(release.version, forKey: ForelightSettings.offeredUpdateVersionKey)
                        presentUpdateAlert(release)
                    }
                } else {
                    availableUpdateVersion = nil
                    if userInitiated {
                        presentSimpleAlert(
                            title: "You're up to date",
                            message: "Forelight \(Self.appShortVersion) is the latest version."
                        )
                    }
                }
            } catch {
                if userInitiated {
                    presentSimpleAlert(title: "Update Check Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func presentUpdateAlert(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Forelight \(release.version) is available"
        var informative = "You are running \(Self.appShortVersion)."
        if let notes = release.notes, !notes.isEmpty {
            informative += "\n\n" + notes.prefix(600)
        }
        alert.informativeText = informative
        alert.addButton(withTitle: release.dmgURL != nil ? "Download" : "Open Release")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let dmgURL = release.dmgURL {
                downloadAndOpen(dmgURL)
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private func downloadAndOpen(_ url: URL) {
        Task { @MainActor in
            do {
                let file = try await UpdateChecker.download(url)
                NSWorkspace.shared.open(file)
            } catch {
                presentSimpleAlert(title: "Download Failed", message: error.localizedDescription)
            }
        }
    }

    private func setAutoCheckForUpdates(_ value: Bool) {
        autoCheckForUpdates = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.autoCheckForUpdatesKey)
        syncModel()
    }

    /// Checks at most once a day, shortly after launch.
    private func scheduleAutomaticUpdateCheck() {
        guard autoCheckForUpdates else { return }
        if let last = UserDefaults.standard.object(forKey: ForelightSettings.lastUpdateCheckKey) as? Date,
           Date().timeIntervalSince(last) < 60 * 60 * 24 {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.checkForUpdates(userInitiated: false)
        }
    }

    private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About Forelight"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.contentViewController = NSHostingController(
                rootView: AboutView(
                    version: Self.appVersion,
                    onOpenSettings: { [weak self] in self?.presentSettings() }
                )
            )
            aboutWindow = window
        }
        presentAuxiliaryWindow(aboutWindow)
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: ForelightSettings.hasCompletedOnboardingKey) else { return }
        // Mark it seen now so it only appears once, however the window is closed.
        UserDefaults.standard.set(true, forKey: ForelightSettings.hasCompletedOnboardingKey)
        showOnboarding()
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Forelight"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.contentViewController = NSHostingController(
                rootView: OnboardingView(
                    model: model,
                    onShortcutChanged: { [weak self] combo in self?.setShortcut(combo) },
                    onShortcutRecordingChanged: { [weak self] recording in self?.setShortcutRecording(recording) },
                    onOpenAccessibilitySettings: { [weak self] in self?.overlayController.openAccessibilitySettings() },
                    onFinish: { [weak self] in self?.finishOnboarding() }
                )
            )
            onboardingWindow = window
        }
        presentAuxiliaryWindow(onboardingWindow)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: ForelightSettings.hasCompletedOnboardingKey)
        onboardingWindow?.close()
    }

    private func presentAuxiliaryWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.appearance = appearanceMode.nsAppearance
        window.backgroundColor = ForelightStyle.windowNSColor
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.level = .modalPanel
    }

    private func setIntensity(_ value: Double) {
        overlayController.setIntensity(value)
        syncModel()
    }

    private func setDisplayedIntensity(_ value: Double) {
        overlayController.setDisplayedIntensity(value)
        syncModel()
    }

    private func toggleCurrentApplicationIntensityOverride() {
        guard let bundleID = overlayController.currentApplicationBundleID else { return }
        if overlayController.currentApplicationHasIntensityOverride {
            // Keep the entry in the list but fall back to the global value.
            overlayController.setAppIntensityEnabled(bundleID: bundleID, enabled: false)
        } else if overlayController.appIntensityStates[bundleID] != nil {
            overlayController.setAppIntensityEnabled(bundleID: bundleID, enabled: true)
        } else {
            overlayController.setAppIntensity(bundleID: bundleID, value: overlayController.intensity)
        }
        refreshUI()
    }

    private func setAppIntensity(bundleID: String, value: Double) {
        overlayController.setAppIntensity(bundleID: bundleID, value: value)
        syncModel()
    }

    private func setAppIntensityEnabled(bundleID: String, enabled: Bool) {
        overlayController.setAppIntensityEnabled(bundleID: bundleID, enabled: enabled)
        refreshUI()
    }

    private func removeAppIntensity(bundleID: String) {
        overlayController.removeAppIntensity(bundleID: bundleID)
        refreshUI()
    }

    private func setDisplayIntensity(displayID: String, value: Double) {
        overlayController.setDisplayIntensity(displayID: displayID, value: value)
        syncModel()
    }

    private func setDisplayDimmingEnabled(displayID: String, enabled: Bool) {
        overlayController.setDisplayDimmingEnabled(displayID: displayID, enabled: enabled)
        refreshUI()
    }

    private func removeDisplayIntensity(displayID: String) {
        overlayController.removeDisplayIntensity(displayID: displayID)
        refreshUI()
    }

    private func setHideWhileMoving(_ value: Bool) {
        overlayController.setHideWhileMoving(value)
        syncModel()
    }

    private func toggleCurrentApplicationExclusion() {
        overlayController.toggleCurrentApplicationExclusion()
        refreshUI()
    }

    private func setFadeDuration(_ value: Double) {
        overlayController.setFadeDuration(value)
        syncModel()
    }

    private func setRestoreDelay(_ value: Double) {
        overlayController.setRestoreDelay(value)
        syncModel()
    }

    private func setSpotlightMode(_ mode: SpotlightMode) {
        overlayController.setSpotlightMode(mode)
        refreshUI()
    }

    private func setSpotlightRadius(_ value: Double) {
        overlayController.setSpotlightRadius(value)
        syncModel()
    }

    private func setSpotlightFeather(_ value: Double) {
        overlayController.setSpotlightFeather(value)
        syncModel()
    }

    private func setCutoutRadius(_ value: Double) {
        overlayController.setCutoutRadius(value)
        syncModel()
    }

    private func setCutoutPadding(_ value: Double) {
        overlayController.setCutoutPadding(value)
        syncModel()
    }

    private func setTint(red: Double, green: Double, blue: Double) {
        overlayController.setTint(red: red, green: green, blue: blue)
        syncModel()
    }

    private func setCutoutAllWindows(_ value: Bool) {
        overlayController.setCutoutAllWindows(value)
        refreshUI()
    }

    private func setCutoutAnimationDuration(_ value: Double) {
        overlayController.setCutoutAnimationDuration(value)
        syncModel()
    }

    private func setVignetteStrength(_ value: Double) {
        overlayController.setVignetteStrength(value)
        syncModel()
    }

    private func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: ForelightSettings.appearanceModeKey)
        popover.appearance = mode.nsAppearance
        settingsWindow?.appearance = mode.nsAppearance
        settingsWindow?.backgroundColor = ForelightStyle.windowNSColor
        syncModel()
    }

    private func setShortcut(_ combo: KeyCombo) {
        shortcut = combo
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: ForelightSettings.shortcutKey)
        }
        configureGlobalShortcut()
        syncModel()
    }

    private func setShortcutRecording(_ recording: Bool) {
        shortcutGate.setSuppressed(recording)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Forelight: could not update login item: \(error.localizedDescription)")
        }
        syncModel()
    }

    private func setException(bundleID: String, enabled: Bool) {
        overlayController.setException(bundleID: bundleID, enabled: enabled)
        refreshUI()
    }
    private func removeException(bundleID: String) {
        overlayController.removeException(bundleID: bundleID)
        refreshUI()
    }

    private func addExceptionFromPanel() {
        for bundleID in chooseApplications(message: "Choose applications to exclude from dimming.") {
            overlayController.addException(bundleID: bundleID)
        }
        refreshUI()
    }

    private func addAppIntensityFromPanel() {
        let value = overlayController.intensity
        for bundleID in chooseApplications(message: "Choose applications to give a custom dim intensity.") {
            overlayController.setAppIntensity(bundleID: bundleID, value: value)
        }
        refreshUI()
    }

    private func chooseApplications(message: String) -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = message

        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func presentSettings(center: Bool = true) {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Forelight Settings"
            window.minSize = NSSize(width: 720, height: 600)
            window.backgroundColor = ForelightStyle.windowNSColor
            window.appearance = appearanceMode.nsAppearance
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }

        if settingsHostingController == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(
                    model: model,
                    onToggleEnabled: { [weak self] value in self?.setEnabled(value) },
                    onIntensityChanged: { [weak self] value in self?.setIntensity(value) },
                    onToggleMoving: { [weak self] value in self?.setHideWhileMoving(value) },
                    onFadeDurationChanged: { [weak self] value in self?.setFadeDuration(value) },
                    onRestoreDelayChanged: { [weak self] value in self?.setRestoreDelay(value) },
                    onSpotlightModeChanged: { [weak self] mode in self?.setSpotlightMode(mode) },
                    onSpotlightRadiusChanged: { [weak self] value in self?.setSpotlightRadius(value) },
                    onSpotlightFeatherChanged: { [weak self] value in self?.setSpotlightFeather(value) },
                    onCutoutRadiusChanged: { [weak self] value in self?.setCutoutRadius(value) },
                    onCutoutPaddingChanged: { [weak self] value in self?.setCutoutPadding(value) },
                    onTintChanged: { [weak self] red, green, blue in self?.setTint(red: red, green: green, blue: blue) },
                    onSetCutoutAllWindows: { [weak self] value in self?.setCutoutAllWindows(value) },
                    onCutoutAnimationChanged: { [weak self] value in self?.setCutoutAnimationDuration(value) },
                    onVignetteChanged: { [weak self] value in self?.setVignetteStrength(value) },
                    onAppearanceModeChanged: { [weak self] mode in self?.setAppearanceMode(mode) },
                    onShortcutChanged: { [weak self] combo in self?.setShortcut(combo) },
                    onShortcutRecordingChanged: { [weak self] recording in self?.setShortcutRecording(recording) },
                    onLaunchAtLoginChanged: { [weak self] value in self?.setLaunchAtLogin(value) },
                    onSetException: { [weak self] bundleID, enabled in self?.setException(bundleID: bundleID, enabled: enabled) },
                    onRemoveException: { [weak self] bundleID in self?.removeException(bundleID: bundleID) },
                    onAddException: { [weak self] in self?.addExceptionFromPanel() },
                    onSetAppIntensity: { [weak self] bundleID, value in self?.setAppIntensity(bundleID: bundleID, value: value) },
                    onSetAppIntensityEnabled: { [weak self] bundleID, enabled in self?.setAppIntensityEnabled(bundleID: bundleID, enabled: enabled) },
                    onRemoveAppIntensity: { [weak self] bundleID in self?.removeAppIntensity(bundleID: bundleID) },
                    onAddAppIntensity: { [weak self] in self?.addAppIntensityFromPanel() },
                    onSetDisplayIntensity: { [weak self] displayID, value in self?.setDisplayIntensity(displayID: displayID, value: value) },
                    onSetDisplayDimmingEnabled: { [weak self] displayID, enabled in self?.setDisplayDimmingEnabled(displayID: displayID, enabled: enabled) },
                    onRemoveDisplayIntensity: { [weak self] displayID in self?.removeDisplayIntensity(displayID: displayID) },
                    onApplyGroup: { [weak self] name in self?.applyGroup(named: name) },
                    onSaveGroup: { [weak self] in self?.saveCurrentAsGroup() },
                    onDeleteGroup: { [weak self] name in self?.deleteGroup(named: name) },
                    onSetGroupShortcut: { [weak self] name, combo in self?.setGroupShortcut(groupName: name, combo: combo) },
                    onGroupShortcutRecordingChanged: { [weak self] recording in self?.setGroupShortcutRecording(recording) },
                    onAddRule: { [weak self] in self?.addRule() },
                    onEditRule: { [weak self] id in self?.editRule(id: id) },
                    onDeleteRule: { [weak self] id in self?.deleteRule(id: id) },
                    onSetRuleEnabled: { [weak self] id, enabled in self?.setRuleEnabled(id: id, enabled: enabled) },
                    onExportSettings: { [weak self] in self?.exportSettings() },
                    onImportSettings: { [weak self] in self?.importSettings() },
                    onResetSettings: { [weak self] in self?.resetSettings() },
                    onShowOnboarding: { [weak self] in self?.showOnboarding() },
                    onShowAbout: { [weak self] in self?.showAbout() },
                    onCheckForUpdates: { [weak self] in self?.checkForUpdates(userInitiated: true) },
                    onSetAutoCheckForUpdates: { [weak self] value in self?.setAutoCheckForUpdates(value) },
                    onOpenAccessibilitySettings: { [weak self] in self?.overlayController.openAccessibilitySettings() }
                )
            )
            settingsHostingController = hostingController
            settingsWindow?.contentViewController = hostingController
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if center {
            settingsWindow?.center()
        }
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.level = .modalPanel
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let settingsVisible = self.settingsWindow?.isVisible == true
            let aboutVisible = self.aboutWindow?.isVisible == true
            let onboardingVisible = self.onboardingWindow?.isVisible == true
            let ruleEditorVisible = self.ruleEditorWindow?.isVisible == true
            if !settingsVisible, !aboutVisible, !onboardingVisible, !ruleEditorVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func toggleEnabled() {
        setEnabled(!enabled)
    }
}
