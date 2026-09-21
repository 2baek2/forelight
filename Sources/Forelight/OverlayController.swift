import AppKit
import ApplicationServices
import CoreGraphics

enum ForelightSettings {
    static let enabledKey = "isEnabled"
    static let intensityKey = "overlayIntensity"
    static let hideWhileMovingKey = "hideWhileMoving"
    static let fadeDurationKey = "dragFadeDuration"
    static let restoreDelayKey = "dragRestoreDelay"
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
    private var excludedBundleIDs: Set<String>
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
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        excludedBundleIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.excludedBundleIDsKey) ?? []
        )
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

    var currentApplicationIsExcluded: Bool {
        guard let bundleIdentifier = currentApplication?.bundleIdentifier else { return false }
        return excludedBundleIDs.contains(bundleIdentifier)
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
        intensity = min(max(value, 0.10), 0.90)
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

        if excludedBundleIDs.contains(bundleIdentifier) {
            excludedBundleIDs.remove(bundleIdentifier)
        } else {
            excludedBundleIDs.insert(bundleIdentifier)
        }
        UserDefaults.standard.set(
            Array(excludedBundleIDs).sorted(),
            forKey: Self.excludedBundleIDsKey
        )
        refresh()
    }

    func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        refresh()
    }

    private func refresh() {
        guard isEnabled else { return }

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
            overlay.update(cutout: cutout, alpha: intensity)
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

private struct WindowSnapshot {
    let bounds: CGRect
}

private enum ActiveWindowLocator {
    static func frontmostWindow(
        on screen: NSScreen,
        excluding ownPID: pid_t,
        preferredOwnerPID: pid_t
    ) -> WindowSnapshot? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        let displayBounds = CGDisplayBounds(displayID)

        guard let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]
              ] else {
            return nil
        }

        var fallback: WindowSnapshot?
        for info in windowInfo {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  !isComputerUseHelper(ownerPID: ownerPID, info: info),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width > 30,
                  bounds.height > 30,
                  bounds.intersects(displayBounds) else {
                continue
            }

            let snapshot = WindowSnapshot(bounds: bounds)
            if ownerPID == preferredOwnerPID {
                return snapshot
            }
            fallback = fallback ?? snapshot
        }

        return fallback
    }

    private static func isComputerUseHelper(ownerPID: pid_t, info: [String: Any]) -> Bool {
        let ownerName = info[kCGWindowOwnerName as String] as? String
        return ownerName?.localizedCaseInsensitiveContains("Computer Use") == true
            || NSRunningApplication(processIdentifier: ownerPID)?.localizedName?.localizedCaseInsensitiveContains("Computer Use") == true
    }
}

private final class OverlayWindow: NSWindow {
    let targetScreen: NSScreen
    private let overlayView: OverlayView
    private var visibilityAnimationID = 0

    init(screen: NSScreen) {
        targetScreen = screen
        overlayView = OverlayView(frame: screen.frame)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = overlayView
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayWindow does not support storyboard decoding")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(cutout: CGRect?, alpha: Double) {
        overlayView.cutout = cutout.map { convertToLocalCoordinates($0) }
        overlayView.alpha = alpha
        overlayView.needsDisplay = true
    }

    func fadeOut(duration: TimeInterval) {
        visibilityAnimationID += 1
        let animationID = visibilityAnimationID

        guard duration > 0 else {
            hideImmediately()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.visibilityAnimationID == animationID else { return }
                self.orderOut(nil)
            }
        }
    }

    func fadeIn(duration: TimeInterval) {
        visibilityAnimationID += 1
        orderFrontRegardless()

        guard duration > 0 else {
            alphaValue = 1
            return
        }

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        }
    }

    func hideImmediately() {
        visibilityAnimationID += 1
        alphaValue = 0
        orderOut(nil)
    }

    func restoreImmediately() {
        visibilityAnimationID += 1
        alphaValue = 1
        if !isVisible {
            orderFrontRegardless()
        }
    }

    private func convertToLocalCoordinates(_ globalFrame: CGRect) -> CGRect {
        globalFrame.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
    }
}

private final class OverlayView: NSView {
    var cutout: CGRect?
    var alpha: Double = 0.45

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let overlayPath = NSBezierPath(rect: bounds)
        if let cutout {
            let safeCutout = cutout.intersection(bounds)
            if !safeCutout.isNull, !safeCutout.isEmpty {
                overlayPath.append(
                    NSBezierPath(
                        roundedRect: safeCutout.insetBy(dx: -2, dy: -2),
                        xRadius: 8,
                        yRadius: 8
                    )
                )
                overlayPath.windingRule = .evenOdd
            }
        }

        NSColor.black.withAlphaComponent(alpha).setFill()
        overlayPath.fill()
    }
}

private extension WindowSnapshot {
    func cocoaFrame(on screen: NSScreen) -> CGRect? {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let displayID else { return nil }

        let quartzDisplayBounds = CGDisplayBounds(displayID)
        let intersection = bounds.intersection(quartzDisplayBounds)
        guard !intersection.isNull, !intersection.isEmpty else { return nil }

        let cocoaX = screen.frame.origin.x + (intersection.origin.x - quartzDisplayBounds.origin.x)
        let cocoaY = screen.frame.origin.y + (quartzDisplayBounds.maxY - intersection.maxY)
        return CGRect(
            x: cocoaX,
            y: cocoaY,
            width: intersection.width,
            height: intersection.height
        )
    }
}
