import AppKit
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
    private var enabled: Bool
    private var appearanceMode: AppearanceMode
    private var shortcut: KeyCombo
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
            snoozeUntil: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureNotifications()
        configureGlobalShortcut()
        overlayController.start()
        overlayController.setEnabled(enabled)
        refreshUI()
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

    private func configureGlobalShortcut() {
        keyboardMonitors.forEach { NSEvent.removeMonitor($0) }
        keyboardMonitors.removeAll()

        // Capture the shortcut by value so the check happens against the combo
        // that was current when the event arrived, not a later edit.
        let expected = shortcut
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard !event.isARepeat, self?.shortcutGate.isSuppressed != true else { return }
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard keyCode == expected.keyCode,
                  modifiers.rawValue == expected.modifiers else { return }
            Task { @MainActor [weak self] in
                self?.toggleEnabled()
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

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
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

    @objc private func snoozeFromMenu(_ sender: NSMenuItem) {
        snooze(forMinutes: sender.tag)
    }

    @objc private func cancelSnoozeFromMenu() {
        cancelSnooze()
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
        NSApp.setActivationPolicy(.accessory)
    }

    private func toggleEnabled() {
        setEnabled(!enabled)
    }
}
