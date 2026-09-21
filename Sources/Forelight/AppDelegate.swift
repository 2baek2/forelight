import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let overlayController = OverlayController()
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var settingsHostingController: NSHostingController<SettingsView>?
    private var enabled = UserDefaults.standard.object(forKey: ForelightSettings.enabledKey) as? Bool ?? true
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var keyboardMonitors: [Any] = []

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

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        refreshPopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func refreshUI() {
        updateStatusItem()
        refreshPopover()
        if settingsWindow?.isVisible == true {
            updateSettingsContent()
        }
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

    private func refreshPopover() {
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView(
                isEnabled: enabled,
                currentApplicationName: overlayController.currentApplicationName,
                currentApplicationIsExcluded: overlayController.currentApplicationIsExcluded,
                intensity: overlayController.intensity,
                hideWhileMoving: overlayController.hideWhileMoving,
                onToggleEnabled: { [weak self] value in self?.setEnabled(value) },
                onIntensityChanged: { [weak self] value in self?.setIntensity(value) },
                onToggleMoving: { [weak self] value in self?.setHideWhileMoving(value) },
                onToggleExclusion: { [weak self] in self?.toggleCurrentApplicationExclusion() },
                onOpenSettings: { [weak self] in self?.presentSettings() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.enabledKey)
        overlayController.setEnabled(value)
        refreshUI()
    }

    private func setIntensity(_ value: Double) {
        overlayController.setIntensity(value)
    }

    private func setHideWhileMoving(_ value: Bool) {
        overlayController.setHideWhileMoving(value)
        refreshPopover()
    }

    private func toggleCurrentApplicationExclusion() {
        overlayController.toggleCurrentApplicationExclusion()
        refreshUI()
    }

    private func setFadeDuration(_ value: Double) {
        overlayController.setFadeDuration(value)
    }

    private func setRestoreDelay(_ value: Double) {
        overlayController.setRestoreDelay(value)
    }

    private func presentSettings(center: Bool = true) {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Forelight Settings"
            window.minSize = NSSize(width: 700, height: 460)
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }

        updateSettingsContent()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if center {
            settingsWindow?.center()
        }
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateSettingsContent() {
        guard let settingsWindow else { return }

        let content = SettingsView(
            isEnabled: enabled,
            currentApplicationName: overlayController.currentApplicationName,
            currentApplicationIsExcluded: overlayController.currentApplicationIsExcluded,
            accessibilityTrusted: overlayController.accessibilityTrusted,
            intensity: overlayController.intensity,
            hideWhileMoving: overlayController.hideWhileMoving,
            fadeDuration: overlayController.fadeDuration,
            restoreDelay: overlayController.restoreDelay,
            onToggleEnabled: { [weak self] value in self?.setEnabled(value) },
            onIntensityChanged: { [weak self] value in self?.setIntensity(value) },
            onToggleMoving: { [weak self] value in self?.setHideWhileMoving(value) },
            onFadeDurationChanged: { [weak self] value in self?.setFadeDuration(value) },
            onRestoreDelayChanged: { [weak self] value in self?.setRestoreDelay(value) },
            onToggleExclusion: { [weak self] in self?.toggleCurrentApplicationExclusion() },
            onOpenAccessibilitySettings: { [weak self] in self?.overlayController.openAccessibilitySettings() }
        )

        if let settingsHostingController {
            settingsHostingController.rootView = content
        } else {
            let hostingController = NSHostingController(rootView: content)
            settingsHostingController = hostingController
            settingsWindow.contentViewController = hostingController
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func toggleEnabled() {
        setEnabled(!enabled)
    }
}
