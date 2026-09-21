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
    static let exceptionsKey = "excludedBundleIDs"
    static let appIntensitiesKey = "appIntensities"
    static let appIntensityEnabledKey = "appIntensityEnabled"
    static let displayIntensitiesKey = "displayIntensities"
    static let displayDimmingDisabledKey = "displayDimmingDisabled"
    static let spotlightModeKey = "spotlightMode"
    static let spotlightRadiusKey = "spotlightRadius"
    static let spotlightFeatherKey = "spotlightFeather"
    static let cutoutRadiusKey = "cutoutCornerRadius"
    static let cutoutPaddingKey = "cutoutPadding"
    static let dimTintKey = "dimTint"
    static let cutoutAllWindowsKey = "cutoutAllWindows"
    static let cutoutAnimationKey = "cutoutAnimationDuration"
    static let vignetteKey = "vignetteStrength"
    static let blurEnabledKey = "blurEnabled"
    static let blurTintRedKey = "blurTintRed"
    static let blurTintGreenKey = "blurTintGreen"
    static let blurTintBlueKey = "blurTintBlue"
    static let blurTintAlphaKey = "blurTintAlpha"
    static let rulesKey = "rules"
    static let focusGroupsKey = "focusGroups"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let intensityRange: ClosedRange<Double> = 0.10...0.90
    static let spotlightRadiusRange: ClosedRange<Double> = 40...400
    static let spotlightFeatherRange: ClosedRange<Double> = 0...160
    static let cutoutRadiusRange: ClosedRange<Double> = 0...40
    static let cutoutPaddingRange: ClosedRange<Double> = 0...40
    static let cutoutAnimationRange: ClosedRange<Double> = 0...0.40
    static let vignetteRange: ClosedRange<Double> = 0...0.80

    /// Every key that holds user settings, used by export, import and reset.
    static let allKeys: [String] = [
        enabledKey,
        intensityKey,
        hideWhileMovingKey,
        fadeDurationKey,
        restoreDelayKey,
        appearanceModeKey,
        shortcutKey,
        exceptionsKey,
        appIntensitiesKey,
        appIntensityEnabledKey,
        displayIntensitiesKey,
        displayDimmingDisabledKey,
        spotlightModeKey,
        spotlightRadiusKey,
        spotlightFeatherKey,
        cutoutRadiusKey,
        cutoutPaddingKey,
        dimTintKey,
        cutoutAllWindowsKey,
        cutoutAnimationKey,
        vignetteKey,
        blurEnabledKey,
        blurTintRedKey,
        blurTintGreenKey,
        blurTintBlueKey,
        blurTintAlphaKey,
        rulesKey,
        focusGroupsKey
    ]

    static func clampedIntensity(_ value: Double) -> Double {
        min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }

    static func effectiveIntensity(global: Double, override: Double?, isEnabled: Bool) -> Double {
        guard let override, isEnabled else { return global }
        return override
    }

    /// A display override wins over an app override, which wins over the global
    /// value.
    static func resolvedIntensity(
        global: Double,
        appOverride: Double?,
        appEnabled: Bool,
        displayOverride: Double?
    ) -> Double {
        if let displayOverride {
            return displayOverride
        }
        return effectiveIntensity(global: global, override: appOverride, isEnabled: appEnabled)
    }
}

@MainActor
final class OverlayController {
    private(set) var intensity: Double {
        didSet {
            UserDefaults.standard.set(intensity, forKey: ForelightSettings.intensityKey)
            refresh()
        }
    }

    private(set) var hideWhileMoving: Bool
    private(set) var fadeDuration: Double
    private(set) var restoreDelay: Double
    private(set) var spotlightMode: SpotlightMode
    private(set) var spotlightRadius: Double
    private(set) var spotlightFeather: Double
    private(set) var cutoutRadius: Double
    private(set) var cutoutPadding: Double
    private(set) var dimTint: DimTint
    private(set) var cutoutAllWindows: Bool
    private(set) var cutoutAnimationDuration: Double
    private(set) var vignetteStrength: Double
    private(set) var blurEnabled: Bool
    private(set) var blurTintRed: Double
    private(set) var blurTintGreen: Double
    private(set) var blurTintBlue: Double
    private(set) var blurTintAlpha: Double
    private var isEnabled = true
    private var exceptions: [String: Bool]
    private var appIntensities: [String: Double]
    private var appIntensityEnabled: [String: Bool]
    private var displayIntensities: [String: Double]
    private var displayDimmingDisabled: [String: Bool]
    private var focusGroupsStorage: [FocusGroup]
    private(set) var activeGroupName: String?
    private var rulesStorage: [Rule]
    private(set) var activeRuleID: UUID?
    var onRuleAction: ((RuleAction) -> Void)?
    private var cachedMicrophoneInUse = false
    private var lastMicrophoneCheck = Date.distantPast
    private var cachedOnBattery: Bool?
    private var lastPowerCheck = Date.distantPast
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
    private var snoozeUntil: Date?
    private var spotlightTimer: Timer?
    private var lastSpotlightLocation: CGPoint = .zero
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        if let stored = UserDefaults.standard.dictionary(forKey: ForelightSettings.exceptionsKey) as? [String: Bool] {
            exceptions = stored
        } else {
            let legacy = UserDefaults.standard.stringArray(forKey: ForelightSettings.exceptionsKey) ?? []
            exceptions = Dictionary(uniqueKeysWithValues: legacy.map { ($0, true) })
        }
        if let raw = UserDefaults.standard.dictionary(forKey: ForelightSettings.appIntensitiesKey) {
            appIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        } else {
            appIntensities = [:]
        }
        if let raw = UserDefaults.standard.dictionary(forKey: ForelightSettings.appIntensityEnabledKey) as? [String: Bool] {
            appIntensityEnabled = raw
        } else {
            appIntensityEnabled = [:]
        }
        if let raw = UserDefaults.standard.dictionary(forKey: ForelightSettings.displayIntensitiesKey) {
            displayIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        } else {
            displayIntensities = [:]
        }
        if let raw = UserDefaults.standard.dictionary(forKey: ForelightSettings.displayDimmingDisabledKey) as? [String: Bool] {
            displayDimmingDisabled = raw
        } else {
            displayDimmingDisabled = [:]
        }
        if let data = UserDefaults.standard.data(forKey: ForelightSettings.focusGroupsKey),
           let groups = try? JSONDecoder().decode([FocusGroup].self, from: data) {
            focusGroupsStorage = groups
        } else {
            focusGroupsStorage = []
        }
        if let data = UserDefaults.standard.data(forKey: ForelightSettings.rulesKey),
           let rules = try? JSONDecoder().decode([Rule].self, from: data) {
            rulesStorage = rules
        } else {
            rulesStorage = []
        }
        let savedIntensity = UserDefaults.standard.double(forKey: ForelightSettings.intensityKey)
        intensity = savedIntensity > 0 ? savedIntensity : 0.45
        let defaults = UserDefaults.standard
        hideWhileMoving = defaults.object(forKey: ForelightSettings.hideWhileMovingKey) as? Bool ?? true
        fadeDuration = defaults.object(forKey: ForelightSettings.fadeDurationKey) as? Double ?? 0.12
        restoreDelay = defaults.object(forKey: ForelightSettings.restoreDelayKey) as? Double ?? 0.05
        spotlightMode = SpotlightMode(rawValue: defaults.string(forKey: ForelightSettings.spotlightModeKey) ?? "") ?? .window
        let savedRadius = defaults.double(forKey: ForelightSettings.spotlightRadiusKey)
        spotlightRadius = savedRadius > 0 ? savedRadius : 120
        spotlightFeather = defaults.object(forKey: ForelightSettings.spotlightFeatherKey) as? Double ?? 40
        cutoutRadius = defaults.object(forKey: ForelightSettings.cutoutRadiusKey) as? Double ?? 8
        cutoutPadding = defaults.object(forKey: ForelightSettings.cutoutPaddingKey) as? Double ?? 2
        dimTint = DimTint(rawValue: defaults.string(forKey: ForelightSettings.dimTintKey) ?? "") ?? .black
        cutoutAllWindows = defaults.object(forKey: ForelightSettings.cutoutAllWindowsKey) as? Bool ?? false
        cutoutAnimationDuration = defaults.object(forKey: ForelightSettings.cutoutAnimationKey) as? Double ?? 0.12
        vignetteStrength = defaults.object(forKey: ForelightSettings.vignetteKey) as? Double ?? 0
        blurEnabled = defaults.bool(forKey: ForelightSettings.blurEnabledKey)
        blurTintRed = defaults.object(forKey: ForelightSettings.blurTintRedKey) as? Double ?? 0
        blurTintGreen = defaults.object(forKey: ForelightSettings.blurTintGreenKey) as? Double ?? 0
        blurTintBlue = defaults.object(forKey: ForelightSettings.blurTintBlueKey) as? Double ?? 0
        blurTintAlpha = defaults.object(forKey: ForelightSettings.blurTintAlphaKey) as? Double ?? 0
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

    /// Intensity that applies to the frontmost app right now: its enabled
    /// per-app override when it has one, otherwise the global value.
    var displayedIntensity: Double {
        guard let bundleID = currentApplication?.bundleIdentifier else { return intensity }
        return ForelightSettings.effectiveIntensity(
            global: intensity,
            override: appIntensities[bundleID],
            isEnabled: isAppIntensityEnabled(bundleID)
        )
    }

    /// Whether the frontmost app has an active (enabled) override.
    var currentApplicationHasIntensityOverride: Bool {
        guard let bundleID = currentApplication?.bundleIdentifier else { return false }
        return appIntensities[bundleID] != nil && isAppIntensityEnabled(bundleID)
    }

    func isAppIntensityEnabled(_ bundleID: String) -> Bool {
        appIntensityEnabled[bundleID] ?? true
    }

    var appIntensityStates: [String: Double] {
        appIntensities
    }

    var appIntensityEnabledStates: [String: Bool] {
        appIntensityEnabled
    }

    func isDisplayDimmingEnabled(_ displayID: String) -> Bool {
        displayDimmingDisabled[displayID] != true
    }

    /// The custom value stored for a display, or the global value as a starting
    /// point when the display has no override yet.
    func displayIntensityValue(for displayID: String) -> Double {
        displayIntensities[displayID] ?? intensity
    }

    var displayIntensityStates: [String: Double] {
        displayIntensities
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
                self?.evaluateRules()
            }
        }

        updateSpotlightTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        spotlightTimer?.invalidate()
        spotlightTimer = nil
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
        updateSpotlightTimer()
    }

    func setIntensity(_ value: Double) {
        intensity = ForelightSettings.clampedIntensity(value)
        activeGroupName = nil
    }

    var isSnoozed: Bool { snoozeUntil != nil }

    var snoozeUntilDate: Date? { snoozeUntil }

    func snooze(until date: Date) {
        snoozeUntil = date
        overlays.forEach { $0.hideImmediately() }
        updateSpotlightTimer()
    }

    func cancelSnooze() {
        snoozeUntil = nil
        updateSpotlightTimer()
        refresh()
    }

    var focusGroups: [FocusGroup] { focusGroupsStorage }

    func saveCurrentAsGroup(named name: String) {
        let existingShortcut = focusGroupsStorage.first(where: { $0.name == name })?.shortcut
        let group = FocusGroup(
            name: name,
            intensity: intensity,
            exceptions: exceptions,
            appIntensities: appIntensities,
            appIntensityEnabled: appIntensityEnabled,
            spotlightMode: spotlightMode,
            spotlightRadius: spotlightRadius,
            spotlightFeather: spotlightFeather,
            displayIntensities: displayIntensities,
            displayDimmingDisabled: displayDimmingDisabled,
            shortcut: existingShortcut
        )
        if let index = focusGroupsStorage.firstIndex(where: { $0.name == name }) {
            focusGroupsStorage[index] = group
        } else {
            focusGroupsStorage.append(group)
        }
        focusGroupsStorage.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistFocusGroups()
        activeGroupName = name
    }

    func applyGroup(named name: String) {
        guard let group = focusGroupsStorage.first(where: { $0.name == name }) else { return }
        intensity = ForelightSettings.clampedIntensity(group.intensity)
        exceptions = group.exceptions
        appIntensities = group.appIntensities
        appIntensityEnabled = group.appIntensityEnabled
        if let mode = group.spotlightMode { spotlightMode = mode }
        if let radius = group.spotlightRadius { spotlightRadius = radius }
        if let feather = group.spotlightFeather { spotlightFeather = feather }
        if let displays = group.displayIntensities { displayIntensities = displays }
        if let disabled = group.displayDimmingDisabled { displayDimmingDisabled = disabled }

        persistExceptions()
        persistAppIntensities()
        persistDisplayIntensities()
        persistSpotlight()
        activeGroupName = name
        updateSpotlightTimer()
        refresh()
    }

    func setGroupShortcut(groupName: String, combo: KeyCombo?) {
        guard let index = focusGroupsStorage.firstIndex(where: { $0.name == groupName }) else { return }
        if let combo {
            for other in focusGroupsStorage.indices where other != index {
                if focusGroupsStorage[other].shortcut == combo {
                    focusGroupsStorage[other].shortcut = nil
                }
            }
        }
        focusGroupsStorage[index].shortcut = combo
        persistFocusGroups()
    }

    func deleteGroup(named name: String) {
        focusGroupsStorage.removeAll { $0.name == name }
        if activeGroupName == name {
            activeGroupName = nil
        }
        persistFocusGroups()
    }

    private func persistFocusGroups() {
        if let data = try? JSONEncoder().encode(focusGroupsStorage) {
            UserDefaults.standard.set(data, forKey: ForelightSettings.focusGroupsKey)
        }
    }

    // MARK: - Rules

    var rules: [Rule] { rulesStorage }

    func addRule(_ rule: Rule) {
        rulesStorage.append(rule)
        persistRules()
        activeRuleID = nil
    }

    func updateRule(_ rule: Rule) {
        if let index = rulesStorage.firstIndex(where: { $0.id == rule.id }) {
            rulesStorage[index] = rule
        } else {
            rulesStorage.append(rule)
        }
        persistRules()
        activeRuleID = nil
    }

    func deleteRule(id: UUID) {
        rulesStorage.removeAll { $0.id == id }
        persistRules()
        activeRuleID = nil
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        guard let index = rulesStorage.firstIndex(where: { $0.id == id }) else { return }
        rulesStorage[index].isEnabled = enabled
        persistRules()
        activeRuleID = nil
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rulesStorage) {
            UserDefaults.standard.set(data, forKey: ForelightSettings.rulesKey)
        }
    }

    private func evaluateRules() {
        guard !rulesStorage.isEmpty else {
            activeRuleID = nil
            return
        }

        let matched = RuleEvaluator.matchedRule(in: rulesStorage, context: makeRuleContext())
        guard matched?.id != activeRuleID else { return }

        activeRuleID = matched?.id
        if let action = matched?.action {
            onRuleAction?(action)
        }
    }

    private func makeRuleContext() -> RuleContext {
        let now = Date()

        if now.timeIntervalSince(lastMicrophoneCheck) > 1 {
            cachedMicrophoneInUse = RuleContextProvider.isMicrophoneInUse()
            lastMicrophoneCheck = now
        }
        if now.timeIntervalSince(lastPowerCheck) > 2 {
            cachedOnBattery = RuleContextProvider.isOnBattery()
            lastPowerCheck = now
        }

        return RuleContext(
            frontmostBundleID: currentApplication?.bundleIdentifier,
            date: now,
            onBattery: cachedOnBattery,
            externalDisplayConnected: RuleContextProvider.hasExternalDisplay(),
            idleSeconds: RuleContextProvider.idleSeconds(),
            microphoneInUse: cachedMicrophoneInUse
        )
    }

    /// Re-reads every stored setting from UserDefaults. Used after importing or
    /// resetting settings.
    func reloadFromDefaults() {
        let defaults = UserDefaults.standard

        if let stored = defaults.dictionary(forKey: ForelightSettings.exceptionsKey) as? [String: Bool] {
            exceptions = stored
        } else {
            let legacy = defaults.stringArray(forKey: ForelightSettings.exceptionsKey) ?? []
            exceptions = Dictionary(uniqueKeysWithValues: legacy.map { ($0, true) })
        }

        if let raw = defaults.dictionary(forKey: ForelightSettings.appIntensitiesKey) {
            appIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        } else {
            appIntensities = [:]
        }

        if let raw = defaults.dictionary(forKey: ForelightSettings.appIntensityEnabledKey) as? [String: Bool] {
            appIntensityEnabled = raw
        } else {
            appIntensityEnabled = [:]
        }

        if let raw = defaults.dictionary(forKey: ForelightSettings.displayIntensitiesKey) {
            displayIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        } else {
            displayIntensities = [:]
        }
        if let raw = defaults.dictionary(forKey: ForelightSettings.displayDimmingDisabledKey) as? [String: Bool] {
            displayDimmingDisabled = raw
        } else {
            displayDimmingDisabled = [:]
        }

        if let data = defaults.data(forKey: ForelightSettings.focusGroupsKey),
           let groups = try? JSONDecoder().decode([FocusGroup].self, from: data) {
            focusGroupsStorage = groups
        } else {
            focusGroupsStorage = []
        }

        if let data = defaults.data(forKey: ForelightSettings.rulesKey),
           let rules = try? JSONDecoder().decode([Rule].self, from: data) {
            rulesStorage = rules
        } else {
            rulesStorage = []
        }
        activeRuleID = nil

        let savedIntensity = defaults.double(forKey: ForelightSettings.intensityKey)
        intensity = savedIntensity > 0 ? ForelightSettings.clampedIntensity(savedIntensity) : 0.45
        hideWhileMoving = defaults.object(forKey: ForelightSettings.hideWhileMovingKey) as? Bool ?? true
        fadeDuration = defaults.object(forKey: ForelightSettings.fadeDurationKey) as? Double ?? 0.12
        restoreDelay = defaults.object(forKey: ForelightSettings.restoreDelayKey) as? Double ?? 0.05
        spotlightMode = SpotlightMode(rawValue: defaults.string(forKey: ForelightSettings.spotlightModeKey) ?? "") ?? .window
        let savedRadius = defaults.double(forKey: ForelightSettings.spotlightRadiusKey)
        spotlightRadius = savedRadius > 0 ? savedRadius : 120
        spotlightFeather = defaults.object(forKey: ForelightSettings.spotlightFeatherKey) as? Double ?? 40
        cutoutRadius = defaults.object(forKey: ForelightSettings.cutoutRadiusKey) as? Double ?? 8
        cutoutPadding = defaults.object(forKey: ForelightSettings.cutoutPaddingKey) as? Double ?? 2
        dimTint = DimTint(rawValue: defaults.string(forKey: ForelightSettings.dimTintKey) ?? "") ?? .black
        cutoutAllWindows = defaults.object(forKey: ForelightSettings.cutoutAllWindowsKey) as? Bool ?? false
        cutoutAnimationDuration = defaults.object(forKey: ForelightSettings.cutoutAnimationKey) as? Double ?? 0.12
        vignetteStrength = defaults.object(forKey: ForelightSettings.vignetteKey) as? Double ?? 0
        blurEnabled = defaults.bool(forKey: ForelightSettings.blurEnabledKey)
        blurTintRed = defaults.object(forKey: ForelightSettings.blurTintRedKey) as? Double ?? 0
        blurTintGreen = defaults.object(forKey: ForelightSettings.blurTintGreenKey) as? Double ?? 0
        blurTintBlue = defaults.object(forKey: ForelightSettings.blurTintBlueKey) as? Double ?? 0
        blurTintAlpha = defaults.object(forKey: ForelightSettings.blurTintAlphaKey) as? Double ?? 0
        activeGroupName = nil
        updateSpotlightTimer()
        refresh()
    }

    /// Edits whatever intensity is in effect for the frontmost app: its enabled
    /// override when present, otherwise the global value.
    func setDisplayedIntensity(_ value: Double) {
        if let bundleID = currentApplication?.bundleIdentifier,
           appIntensities[bundleID] != nil,
           isAppIntensityEnabled(bundleID) {
            setAppIntensity(bundleID: bundleID, value: value)
        } else {
            setIntensity(value)
        }
    }

    func setAppIntensity(bundleID: String, value: Double) {
        appIntensities[bundleID] = ForelightSettings.clampedIntensity(value)
        if appIntensityEnabled[bundleID] == nil {
            appIntensityEnabled[bundleID] = true
        }
        persistAppIntensities()
        refresh()
    }

    func setAppIntensityEnabled(bundleID: String, enabled: Bool) {
        appIntensityEnabled[bundleID] = enabled
        persistAppIntensities()
        refresh()
    }

    func removeAppIntensity(bundleID: String) {
        appIntensities.removeValue(forKey: bundleID)
        appIntensityEnabled.removeValue(forKey: bundleID)
        persistAppIntensities()
        refresh()
    }

    private func persistAppIntensities() {
        UserDefaults.standard.set(appIntensities, forKey: ForelightSettings.appIntensitiesKey)
        UserDefaults.standard.set(appIntensityEnabled, forKey: ForelightSettings.appIntensityEnabledKey)
        activeGroupName = nil
    }

    func setDisplayIntensity(displayID: String, value: Double) {
        displayIntensities[displayID] = ForelightSettings.clampedIntensity(value)
        persistDisplayIntensities()
        refresh()
    }

    func setDisplayDimmingEnabled(displayID: String, enabled: Bool) {
        if enabled {
            displayDimmingDisabled.removeValue(forKey: displayID)
        } else {
            displayDimmingDisabled[displayID] = true
        }
        persistDisplayIntensities()
        refresh()
    }

    func removeDisplayIntensity(displayID: String) {
        displayIntensities.removeValue(forKey: displayID)
        persistDisplayIntensities()
        refresh()
    }

    private func persistDisplayIntensities() {
        UserDefaults.standard.set(displayIntensities, forKey: ForelightSettings.displayIntensitiesKey)
        UserDefaults.standard.set(displayDimmingDisabled, forKey: ForelightSettings.displayDimmingDisabledKey)
        activeGroupName = nil
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

    func setSpotlightMode(_ mode: SpotlightMode) {
        spotlightMode = mode
        persistSpotlight()
        updateSpotlightTimer()
        refresh()
    }

    func setSpotlightRadius(_ value: Double) {
        spotlightRadius = min(
            max(value, ForelightSettings.spotlightRadiusRange.lowerBound),
            ForelightSettings.spotlightRadiusRange.upperBound
        )
        persistSpotlight()
        refreshSpotlight()
    }

    func setSpotlightFeather(_ value: Double) {
        spotlightFeather = min(
            max(value, ForelightSettings.spotlightFeatherRange.lowerBound),
            ForelightSettings.spotlightFeatherRange.upperBound
        )
        persistSpotlight()
        refreshSpotlight()
    }

    private func persistSpotlight() {
        let defaults = UserDefaults.standard
        defaults.set(spotlightMode.rawValue, forKey: ForelightSettings.spotlightModeKey)
        defaults.set(spotlightRadius, forKey: ForelightSettings.spotlightRadiusKey)
        defaults.set(spotlightFeather, forKey: ForelightSettings.spotlightFeatherKey)
        activeGroupName = nil
    }

    func setCutoutRadius(_ value: Double) {
        cutoutRadius = min(
            max(value, ForelightSettings.cutoutRadiusRange.lowerBound),
            ForelightSettings.cutoutRadiusRange.upperBound
        )
        UserDefaults.standard.set(cutoutRadius, forKey: ForelightSettings.cutoutRadiusKey)
        refresh()
    }

    func setCutoutPadding(_ value: Double) {
        cutoutPadding = min(
            max(value, ForelightSettings.cutoutPaddingRange.lowerBound),
            ForelightSettings.cutoutPaddingRange.upperBound
        )
        UserDefaults.standard.set(cutoutPadding, forKey: ForelightSettings.cutoutPaddingKey)
        refresh()
    }

    func setDimTint(_ tint: DimTint) {
        dimTint = tint
        UserDefaults.standard.set(tint.rawValue, forKey: ForelightSettings.dimTintKey)
        refresh()
    }

    func setCutoutAllWindows(_ value: Bool) {
        cutoutAllWindows = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.cutoutAllWindowsKey)
        refresh()
    }

    func setCutoutAnimationDuration(_ value: Double) {
        cutoutAnimationDuration = min(
            max(value, ForelightSettings.cutoutAnimationRange.lowerBound),
            ForelightSettings.cutoutAnimationRange.upperBound
        )
        UserDefaults.standard.set(cutoutAnimationDuration, forKey: ForelightSettings.cutoutAnimationKey)
    }

    func setVignetteStrength(_ value: Double) {
        vignetteStrength = min(
            max(value, ForelightSettings.vignetteRange.lowerBound),
            ForelightSettings.vignetteRange.upperBound
        )
        UserDefaults.standard.set(vignetteStrength, forKey: ForelightSettings.vignetteKey)
        refresh()
    }

    func setBlurEnabled(_ value: Bool) {
        blurEnabled = value
        UserDefaults.standard.set(value, forKey: ForelightSettings.blurEnabledKey)
        refresh()
    }

    func setBlurTint(red: Double, green: Double, blue: Double, alpha: Double) {
        blurTintRed = min(max(red, 0), 1)
        blurTintGreen = min(max(green, 0), 1)
        blurTintBlue = min(max(blue, 0), 1)
        blurTintAlpha = min(max(alpha, 0), 1)

        let defaults = UserDefaults.standard
        defaults.set(blurTintRed, forKey: ForelightSettings.blurTintRedKey)
        defaults.set(blurTintGreen, forKey: ForelightSettings.blurTintGreenKey)
        defaults.set(blurTintBlue, forKey: ForelightSettings.blurTintBlueKey)
        defaults.set(blurTintAlpha, forKey: ForelightSettings.blurTintAlphaKey)
        refresh()
    }

    private var dimStyle: DimStyle {
        DimStyle(
            cornerRadius: cutoutRadius,
            padding: cutoutPadding,
            tint: dimTint,
            vignette: vignetteStrength,
            blurEnabled: blurEnabled,
            blurTint: blurTintAlpha > 0
                ? NSColor(srgbRed: blurTintRed, green: blurTintGreen, blue: blurTintBlue, alpha: blurTintAlpha)
                : nil
        )
    }

    private func updateSpotlightTimer() {
        let needsSpotlight = isEnabled && !isSnoozed && spotlightMode.includesCursor
        if needsSpotlight {
            guard spotlightTimer == nil else { return }
            lastSpotlightLocation = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
            spotlightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tickSpotlight()
                }
            }
        } else {
            spotlightTimer?.invalidate()
            spotlightTimer = nil
            overlays.forEach { $0.clearSpotlight() }
        }
    }

    private func tickSpotlight() {
        guard isEnabled, !isSnoozed, spotlightMode.includesCursor else { return }
        guard !MissionControlDetector.isActive(), !currentApplicationIsExcluded else {
            overlays.forEach { $0.clearSpotlight() }
            return
        }

        let location = NSEvent.mouseLocation
        if abs(location.x - lastSpotlightLocation.x) < 0.5,
           abs(location.y - lastSpotlightLocation.y) < 0.5 {
            return
        }
        lastSpotlightLocation = location

        for overlay in overlays {
            overlay.updateSpotlight(
                globalCenter: location,
                radius: spotlightRadius,
                feather: spotlightFeather
            )
        }
    }

    private func refreshSpotlight() {
        lastSpotlightLocation = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        tickSpotlight()
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
        UserDefaults.standard.set(exceptions, forKey: ForelightSettings.exceptionsKey)
        activeGroupName = nil
    }

    func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        refresh()
    }

    private func refresh() {
        guard isEnabled else { return }

        if let until = snoozeUntil, Date() >= until {
            snoozeUntil = nil
        }
        if snoozeUntil != nil {
            overlays.forEach { $0.hideImmediately() }
            return
        }

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
            if let displayID = DisplayIdentifier.info(for: overlay.targetScreen)?.id,
               !isDisplayDimmingEnabled(displayID) {
                overlay.hideImmediately()
                continue
            }

            overlay.update(
                cutouts: cutouts(for: overlay),
                alpha: resolvedIntensity(for: overlay.targetScreen),
                style: dimStyle,
                animationDuration: cutoutAnimationDuration
            )
            overlay.restoreImmediately()
        }
    }

    func resolvedIntensity(for screen: NSScreen) -> Double {
        let displayID = DisplayIdentifier.info(for: screen)?.id
        let displayOverride = displayID.flatMap { displayIntensities[$0] }
        let bundleID = currentApplication?.bundleIdentifier
        let appOverride = bundleID.flatMap { appIntensities[$0] }
        let appEnabled = bundleID.map { isAppIntensityEnabled($0) } ?? false

        return ForelightSettings.resolvedIntensity(
            global: intensity,
            appOverride: appOverride,
            appEnabled: appEnabled,
            displayOverride: displayOverride
        )
    }

    /// The window cutouts for one overlay: either every window of the frontmost
    /// app, or just the focused window.
    private func cutouts(for overlay: OverlayWindow) -> [CGRect] {
        guard spotlightMode.includesWindow else { return [] }

        if cutoutAllWindows {
            let frames = allWindowFrames(for: overlay)
            if !frames.isEmpty {
                return frames
            }
        }

        if let frame = focusedWindowFrame {
            let intersection = frame.intersection(overlay.frame)
            if !intersection.isNull, !intersection.isEmpty {
                return [intersection]
            }
        }

        if let snapshot = ActiveWindowLocator.frontmostWindow(
            on: overlay.targetScreen,
            excluding: ownPID,
            preferredOwnerPID: observedPID
        ), let frame = snapshot.cocoaFrame(on: overlay.targetScreen) {
            return [frame]
        }

        return []
    }

    private func allWindowFrames(for overlay: OverlayWindow) -> [CGRect] {
        if AXIsProcessTrusted(), let axApplication {
            let frames = axWindowFrames(axApplication).compactMap { frame -> CGRect? in
                let intersection = frame.intersection(overlay.frame)
                return intersection.isNull || intersection.isEmpty ? nil : intersection
            }
            if !frames.isEmpty {
                return frames
            }
        }

        guard observedPID != 0 else { return [] }
        return ActiveWindowLocator.windows(on: overlay.targetScreen, ownerPID: observedPID)
            .compactMap { $0.cocoaFrame(on: overlay.targetScreen) }
    }

    private func axWindowFrames(_ application: AXUIElement) -> [CGRect] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let windows = value as? [AXUIElement] else {
            return []
        }
        return windows.compactMap { frame(of: $0) }
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

        focusedWindowFrame = frame(of: axFocusedWindow)
    }

    /// Reads an accessibility element's frame and converts it into Cocoa global
    /// coordinates.
    private func frame(of element: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, 0.4)

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionAXValue = axValue(positionValue),
        let sizeAXValue = axValue(sizeValue),
        let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              size.width > 30,
              size.height > 30 else {
            return nil
        }

        return CGRect(
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
