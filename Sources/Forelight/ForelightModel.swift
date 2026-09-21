import AppKit
import Combine

struct ExceptionEntry: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    var isEnabled: Bool

    var id: String { bundleID }
}

struct AppIntensityEntry: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    var value: Double
    var isEnabled: Bool

    var id: String { bundleID }
}

struct DisplayIntensityEntry: Identifiable {
    let id: String
    let name: String
    var value: Double
    var hasOverride: Bool
    var isDimmingEnabled: Bool
}

enum AppInfoResolver {
    static func resolve(bundleID: String) -> (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (bundleID, nil)
        }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (name, NSWorkspace.shared.icon(forFile: url.path))
    }
}

@MainActor
final class ForelightModel: ObservableObject {
    @Published var isEnabled: Bool
    @Published var currentApplicationName: String?
    @Published var currentApplicationIsExcluded: Bool
    @Published var accessibilityTrusted: Bool
    @Published var intensity: Double
    @Published var hideWhileMoving: Bool
    @Published var fadeDuration: Double
    @Published var restoreDelay: Double
    @Published var exceptions: [ExceptionEntry]
    @Published var appearanceMode: AppearanceMode
    @Published var shortcut: KeyCombo
    @Published var launchAtLogin: Bool
    @Published var effectiveIntensity: Double
    @Published var currentApplicationHasIntensityOverride: Bool
    @Published var appIntensityOverrides: [AppIntensityEntry]
    @Published var isSnoozed: Bool
    @Published var snoozeUntil: Date?
    @Published var focusGroups: [FocusGroup]
    @Published var activeGroupName: String?
    @Published var displays: [DisplayIntensityEntry]
    @Published var spotlightMode: SpotlightMode
    @Published var spotlightRadius: Double
    @Published var spotlightFeather: Double
    @Published var cutoutRadius: Double
    @Published var cutoutPadding: Double
    @Published var dimTint: DimTint

    init(
        isEnabled: Bool,
        currentApplicationName: String?,
        currentApplicationIsExcluded: Bool,
        accessibilityTrusted: Bool,
        intensity: Double,
        hideWhileMoving: Bool,
        fadeDuration: Double,
        restoreDelay: Double,
        exceptions: [ExceptionEntry],
        appearanceMode: AppearanceMode,
        shortcut: KeyCombo,
        launchAtLogin: Bool,
        effectiveIntensity: Double,
        currentApplicationHasIntensityOverride: Bool,
        appIntensityOverrides: [AppIntensityEntry],
        isSnoozed: Bool,
        snoozeUntil: Date?,
        focusGroups: [FocusGroup],
        activeGroupName: String?,
        displays: [DisplayIntensityEntry],
        spotlightMode: SpotlightMode,
        spotlightRadius: Double,
        spotlightFeather: Double,
        cutoutRadius: Double,
        cutoutPadding: Double,
        dimTint: DimTint
    ) {
        self.isEnabled = isEnabled
        self.currentApplicationName = currentApplicationName
        self.currentApplicationIsExcluded = currentApplicationIsExcluded
        self.accessibilityTrusted = accessibilityTrusted
        self.intensity = intensity
        self.hideWhileMoving = hideWhileMoving
        self.fadeDuration = fadeDuration
        self.restoreDelay = restoreDelay
        self.exceptions = exceptions
        self.appearanceMode = appearanceMode
        self.shortcut = shortcut
        self.launchAtLogin = launchAtLogin
        self.effectiveIntensity = effectiveIntensity
        self.currentApplicationHasIntensityOverride = currentApplicationHasIntensityOverride
        self.appIntensityOverrides = appIntensityOverrides
        self.isSnoozed = isSnoozed
        self.snoozeUntil = snoozeUntil
        self.focusGroups = focusGroups
        self.activeGroupName = activeGroupName
        self.displays = displays
        self.spotlightMode = spotlightMode
        self.spotlightRadius = spotlightRadius
        self.spotlightFeather = spotlightFeather
        self.cutoutRadius = cutoutRadius
        self.cutoutPadding = cutoutPadding
        self.dimTint = dimTint
    }
}
