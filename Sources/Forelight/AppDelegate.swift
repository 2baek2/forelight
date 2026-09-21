import AppKit
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
            appearanceMode: appearanceMode
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
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp])
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = appearanceMode.nsAppearance
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView(
                model: model,
                onToggleEnabled: { [weak self] value in self?.setEnabled(value) },
                onIntensityChanged: { [weak self] value in self?.setIntensity(value) },
                onToggleMoving: { [weak self] value in self?.setHideWhileMoving(value) },
                onToggleExclusion: { [weak self] in self?.toggleCurrentApplicationExclusion() },
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
        let handler: (NSEvent) -> Void = { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 3,
                  modifiers == [.command, .option],
                  !event.isARepeat else { return }
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
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: enabled ? "Forelight enabled" : "Forelight disabled"
        )
        let appName = overlayController.currentApplicationName ?? "No active app"
        statusItem.button?.toolTip = enabled ? "Forelight · " + appName : "Forelight paused"
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.enabledKey)
        overlayController.setEnabled(value)
        refreshUI()
    }

    private func setIntensity(_ value: Double) {
        overlayController.setIntensity(value)
        syncModel()
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

    private func setException(bundleID: String, enabled: Bool) {
        overlayController.setException(bundleID: bundleID, enabled: enabled)
        refreshUI()
    }
    private func removeException(bundleID: String) {
        overlayController.removeException(bundleID: bundleID)
        refreshUI()
    }

    private func addExceptionFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = "Choose applications to exclude from dimming."

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                overlayController.addException(bundleID: bundleID)
            }
        }
        refreshUI()
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
                    onSetException: { [weak self] bundleID, enabled in self?.setException(bundleID: bundleID, enabled: enabled) },
                    onRemoveException: { [weak self] bundleID in self?.removeException(bundleID: bundleID) },
                    onAddException: { [weak self] in self?.addExceptionFromPanel() },
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
