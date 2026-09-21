import AppKit
import ApplicationServices
import CoreGraphics

enum ForelightSettings {
    static let enabledKey = "isEnabled"
    static let intensityKey = "overlayIntensity"
    static let hideWhileMovingKey = "hideWhileMoving"
    static let fadeDurationKey = "dragFadeDuration"
    static let restoreDelayKey = "dragRestoreDelay"
    static let appearanceModeKey = "appearanceMode"
    static let shortcutKey = "globalShortcut"
    static let appIntensitiesKey = "appIntensities"
    static let intensityRange: ClosedRange<Double> = 0.10...0.90

    static func clampedIntensity(_ value: Double) -> Double {
        min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }
}

@MainActor
final class OverlayController {
    private static let excludedBundleIDsKey = "excludedBundleIDs"

    private(set) var intensity: Double {
        didSet {
            UserDefaults.standard.set(intensity, forKey: ForelightSettings.intensityKey)
            refresh()
        }
    }

    private(set) var hideWhileMoving: Bool
    private(set) var fadeDuration: Double
    private(set) var restoreDelay: Double
    private var isEnabled = true
    private var exceptions: [String: Bool]
    private var appIntensities: [String: Double]
    private var currentApplication: NSRunningApplication?
    private var isDraggingWindow = false
    private var mouseButtonDown = false
    private var overlays: [OverlayWindow] = []
    private var refreshTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var mouseObservers: [Any] = []
    private var axObserver: AXObserver?
    private var axApplication: AXUIElement?
    private var axFocusedWindow: AXUIElement?
    private var focusedWindowFrame: CGRect?
    private var observedPID: pid_t = 0
    private var dragEndFailsafe: DispatchWorkItem?
    private var dragRestoreWorkItem: DispatchWorkItem?
    private var isMissionControlActive = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        if let stored = UserDefaults.standard.dictionary(forKey: Self.excludedBundleIDsKey) as? [String: Bool] {
            exceptions = stored
        } else {
            let legacy = UserDefaults.standard.stringArray(forKey: Self.excludedBundleIDsKey) ?? []
            exceptions = Dictionary(uniqueKeysWithValues: legacy.map { ($0, true) })
        }
        if let raw = UserDefaults.standard.dictionary(forKey: ForelightSettings.appIntensitiesKey) {
            appIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        } else {
            appIntensities = [:]
        }
        let savedIntensity = UserDefaults.standard.double(forKey: ForelightSettings.intensityKey)
        intensity = savedIntensity > 0 ? savedIntensity : 0.45
        let defaults = UserDefaults.standard
        hideWhileMoving = defaults.object(forKey: ForelightSettings.hideWhileMovingKey) as? Bool ?? true
        fadeDuration = defaults.object(forKey: ForelightSettings.fadeDurationKey) as? Double ?? 0.12
        restoreDelay = defaults.object(forKey: ForelightSettings.restoreDelayKey) as? Double ?? 0.05
    }

    var currentApplicationName: String? {
        currentApplication?.localizedName
    }

    var currentApplicationBundleID: String? {
        currentApplication?.bundleIdentifier
    }

    var currentApplicationIsExcluded: Bool {
        guard let bundleIdentifier = currentApplication?.bundleIdentifier else { return false }
        return exceptions[bundleIdentifier] == true
    }

    var exceptionStates: [String: Bool] {
        exceptions
    }

    /// Intensity that applies to the frontmost app right now: its per-app
    /// override when it has one, otherwise the global value.
    var displayedIntensity: Double {
        if let bundleID = currentApplication?.bundleIdentifier,
           let override = appIntensities[bundleID] {
            return override
        }
        return intensity
    }

    var currentApplicationIntensityOverride: Double? {
        guard let bundleID = currentApplication?.bundleIdentifier else { return nil }
        return appIntensities[bundleID]
    }

    var appIntensityStates: [String: Double] {
        appIntensities
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func start() {
        requestAccessibilityPermissionIfNeeded()
        rebuildOverlays()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.attachToFrontmostApplication()
            }
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        addMouseObservers()
        attachToFrontmostApplication()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.attachToFrontmostApplication()
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        activationObserver = nil
        spaceObserver = nil
        mouseObservers.forEach { NSEvent.removeMonitor($0) }
        mouseObservers.removeAll()
        removeAXObserver()
        dragEndFailsafe?.cancel()
        dragEndFailsafe = nil
        dragRestoreWorkItem?.cancel()
        dragRestoreWorkItem = nil
        overlays.forEach { $0.hideImmediately() }
        overlays.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            if !isDraggingWindow {
                refresh()
            }
        } else {
            mouseButtonDown = false
            isDraggingWindow = false
            dragEndFailsafe?.cancel()
            dragEndFailsafe = nil
            dragRestoreWorkItem?.cancel()
            dragRestoreWorkItem = nil
            overlays.forEach { $0.hideImmediately() }
        }
    }

    func setIntensity(_ value: Double) {
        intensity = ForelightSettings.clampedIntensity(value)
    }

    /// Edits whatever intensity is in effect for the frontmost app: its override
    /// when present, otherwise the global value.
    func setDisplayedIntensity(_ value: Double) {
        if let bundleID = currentApplication?.bundleIdentifier, appIntensities[bundleID] != nil {
            setAppIntensity(bundleID: bundleID, value: value)
        } else {
            setIntensity(value)
        }
    }

    func setAppIntensity(bundleID: String, value: Double) {
        appIntensities[bundleID] = ForelightSettings.clampedIntensity(value)
        persistAppIntensities()
        refresh()
    }

    func removeAppIntensity(bundleID: String) {
        appIntensities.removeValue(forKey: bundleID)
        persistAppIntensities()
        refresh()
    }

    private func persistAppIntensities() {
        UserDefaults.standard.set(appIntensities, forKey: ForelightSettings.appIntensitiesKey)
    }

    func setHideWhileMoving(_ value: Bool) {
        hideWhileMoving = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.hideWhileMovingKey)
        if isDraggingWindow {
            if value {
                overlays.forEach { $0.fadeOut(duration: fadeDuration) }
            } else {
                overlays.forEach { $0.restoreImmediately() }
                refresh()
            }
        }
    }

    func setFadeDuration(_ value: Double) {
        fadeDuration = min(max(value, 0), 0.35)
        UserDefaults.standard.set(fadeDuration, forKey: ForelightSettings.fadeDurationKey)
    }

    func setRestoreDelay(_ value: Double) {
        restoreDelay = min(max(value, 0), 0.30)
        UserDefaults.standard.set(restoreDelay, forKey: ForelightSettings.restoreDelayKey)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshFrontmostApplication() {
        attachToFrontmostApplication()
    }

    func toggleCurrentApplicationExclusion() {
        guard let bundleIdentifier = currentApplication?.bundleIdentifier else { return }
        setException(bundleID: bundleIdentifier, enabled: exceptions[bundleIdentifier] != true)
    }

    func addException(bundleID: String) {
        exceptions[bundleID] = true
        persistExceptions()
        refresh()
    }

    func setException(bundleID: String, enabled: Bool) {
        exceptions[bundleID] = enabled
        persistExceptions()
        refresh()
    }

    func removeException(bundleID: String) {
        exceptions.removeValue(forKey: bundleID)
        persistExceptions()
        refresh()
    }

    private func persistExceptions() {
        UserDefaults.standard.set(exceptions, forKey: Self.excludedBundleIDsKey)
    }

    func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        refresh()
    }

    private func refresh() {
        guard isEnabled else { return }

        if MissionControlDetector.isActive() {
            if !isMissionControlActive {
                isMissionControlActive = true
                overlays.forEach { $0.hideImmediately() }
            }
            return
        }
        isMissionControlActive = false

        if currentApplicationIsExcluded {
            overlays.forEach { $0.hideImmediately() }
            return
        }

        guard !isDraggingWindow || !hideWhileMoving else { return }

        if overlays.count != NSScreen.screens.count {
            rebuildOverlays()
            return
        }

        for overlay in overlays {
            let cutout = focusedWindowFrame.flatMap { frame in
                let intersection = frame.intersection(overlay.frame)
                return intersection.isNull || intersection.isEmpty ? nil : intersection
            } ?? ActiveWindowLocator.frontmostWindow(
                on: overlay.targetScreen,
                excluding: ProcessInfo.processInfo.processIdentifier,
                preferredOwnerPID: observedPID
            )?.cocoaFrame(on: overlay.targetScreen)
            overlay.update(cutout: cutout, alpha: displayedIntensity)
            overlay.restoreImmediately()
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func addMouseObservers() {
        if let observer = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mouseButtonDown = true
            }
        }) {
            mouseObservers.append(observer)
        }

        if let observer = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endWindowDrag()
            }
        }) {
            mouseObservers.append(observer)
        }

        if let observer = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.mouseButtonDown = true
            }
            return event
        }) {
            mouseObservers.append(observer)
        }

        if let observer = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.endWindowDrag()
            }
            return event
        }) {
            mouseObservers.append(observer)
        }
    }

    private func attachToFrontmostApplication() {
        guard let application = frontmostApplication(),
              application.processIdentifier != ownPID else {
            refresh()
            return
        }

        currentApplication = application
        attachAXObserver(to: application.processIdentifier)
        refresh()
    }

    private func frontmostApplication() -> NSRunningApplication? {
        if AXIsProcessTrusted() {
            let systemWideElement = AXUIElementCreateSystemWide()
            var focusedApplicationValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                systemWideElement,
                kAXFocusedApplicationAttribute as CFString,
                &focusedApplicationValue
            ) == .success,
            let focusedApplication = axElement(focusedApplicationValue) {
                var pid: pid_t = 0
                if AXUIElementGetPid(focusedApplication, &pid) == .success,
                   let application = NSRunningApplication(processIdentifier: pid) {
                    return application
                }
            }
        }

        return NSWorkspace.shared.frontmostApplication
    }

    private func attachAXObserver(to pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        guard observedPID != pid || axObserver == nil else {
            refreshFocusedWindowFrame()
            return
        }

        removeAXObserver()
        observedPID = pid
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        axApplication = application

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<OverlayController>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            Task { @MainActor [weak controller] in
                guard let controller else { return }
                if name == kAXFocusedWindowChangedNotification || name == kAXMainWindowChangedNotification {
                    controller.refreshFocusedWindowObservation()
                } else if name == kAXWindowMovedNotification || name == kAXWindowResizedNotification {
                    controller.refreshFocusedWindowFrame()
                    controller.noteWindowGeometryChanging()
                }
                controller.refresh()
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success,
              let observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            observer,
            application,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        AXObserverAddNotification(
            observer,
            application,
            kAXMainWindowChangedNotification as CFString,
            refcon
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        axObserver = observer
        refreshFocusedWindowObservation()
    }

    private func refreshFocusedWindowObservation() {
        guard let axObserver, let axApplication else { return }

        if let axFocusedWindow {
            AXObserverRemoveNotification(axObserver, axFocusedWindow, kAXWindowMovedNotification as CFString)
            AXObserverRemoveNotification(axObserver, axFocusedWindow, kAXWindowResizedNotification as CFString)
        }
        axFocusedWindow = nil
        focusedWindowFrame = nil

        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApplication,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindow = axElement(focusedWindowValue) else { return }
        AXUIElementSetMessagingTimeout(focusedWindow, 0.4)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            axObserver,
            focusedWindow,
            kAXWindowMovedNotification as CFString,
            refcon
        )
        AXObserverAddNotification(
            axObserver,
            focusedWindow,
            kAXWindowResizedNotification as CFString,
            refcon
        )
        axFocusedWindow = focusedWindow
        refreshFocusedWindowFrame()
    }

    private func refreshFocusedWindowFrame() {
        guard let axFocusedWindow,
              !isComputerUseHelperWindow else {
            focusedWindowFrame = nil
            return
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axFocusedWindow,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            axFocusedWindow,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionAXValue = axValue(positionValue),
        let sizeAXValue = axValue(sizeValue) else {
            focusedWindowFrame = nil
            return
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              size.width > 30,
              size.height > 30,
              let primaryScreen = NSScreen.screens.first else {
            focusedWindowFrame = nil
            return
        }

        focusedWindowFrame = CGRect(
            x: position.x,
            y: primaryScreen.frame.maxY - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private var isComputerUseHelperWindow: Bool {
        guard observedPID != 0,
              let name = NSRunningApplication(processIdentifier: observedPID)?.localizedName else {
            return false
        }
        return name.localizedCaseInsensitiveContains("Computer Use")
    }

    private func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private func removeAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(axObserver),
                .defaultMode
            )
        }
        axObserver = nil
        axApplication = nil
        axFocusedWindow = nil
        focusedWindowFrame = nil
        observedPID = 0
    }

    private func noteWindowGeometryChanging() {
        guard mouseButtonDown else { return }
        setDraggingWindow(true)

        dragEndFailsafe?.cancel()
        let failsafe = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.endWindowDrag()
            }
        }
        dragEndFailsafe = failsafe
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: failsafe)
    }

    private func endWindowDrag() {
        mouseButtonDown = false
        dragEndFailsafe?.cancel()
        dragEndFailsafe = nil
        dragRestoreWorkItem?.cancel()
        dragRestoreWorkItem = nil
        setDraggingWindow(false)
    }

    private func setDraggingWindow(_ dragging: Bool) {
        guard isDraggingWindow != dragging else { return }
        isDraggingWindow = dragging

        if dragging {
            dragRestoreWorkItem?.cancel()
            dragRestoreWorkItem = nil
            if hideWhileMoving {
                overlays.forEach { $0.fadeOut(duration: fadeDuration) }
            }
        } else if !isEnabled {
            overlays.forEach { $0.hideImmediately() }
        } else if !hideWhileMoving {
            refresh()
        } else {
            let restore = DispatchWorkItem { [weak self] in
                guard let self, !self.isDraggingWindow else { return }
                self.refresh()
                self.overlays.forEach { $0.fadeIn(duration: self.fadeDuration) }
            }
            dragRestoreWorkItem = restore
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: restore)
        }
    }
}
