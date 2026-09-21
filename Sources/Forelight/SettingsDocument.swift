import Foundation

/// A portable snapshot of every Forelight setting, used for export, import and
/// reset. All fields are optional so older or partial files still load.
struct SettingsDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var isEnabled: Bool?
    var intensity: Double?
    var hideWhileMoving: Bool?
    var fadeDuration: Double?
    var restoreDelay: Double?
    var appearanceMode: String?
    var shortcut: KeyCombo?
    var launchAtLogin: Bool?
    var exceptions: [String: Bool]?
    var appIntensities: [String: Double]?
    var appIntensityEnabled: [String: Bool]?
    var displayIntensities: [String: Double]?
    var displayDimmingDisabled: [String: Bool]?
    var focusGroups: [FocusGroup]?

    init(version: Int = SettingsDocument.currentVersion) {
        self.version = version
    }

    static func load(from defaults: UserDefaults) -> SettingsDocument {
        var document = SettingsDocument()

        document.isEnabled = defaults.object(forKey: ForelightSettings.enabledKey) as? Bool
        let intensity = defaults.double(forKey: ForelightSettings.intensityKey)
        document.intensity = intensity > 0 ? intensity : nil
        document.hideWhileMoving = defaults.object(forKey: ForelightSettings.hideWhileMovingKey) as? Bool
        document.fadeDuration = defaults.object(forKey: ForelightSettings.fadeDurationKey) as? Double
        document.restoreDelay = defaults.object(forKey: ForelightSettings.restoreDelayKey) as? Double
        document.appearanceMode = defaults.string(forKey: ForelightSettings.appearanceModeKey)

        if let data = defaults.data(forKey: ForelightSettings.shortcutKey) {
            document.shortcut = try? JSONDecoder().decode(KeyCombo.self, from: data)
        }
        document.exceptions = defaults.dictionary(forKey: ForelightSettings.exceptionsKey) as? [String: Bool]
        if let raw = defaults.dictionary(forKey: ForelightSettings.appIntensitiesKey) {
            document.appIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        document.appIntensityEnabled = defaults.dictionary(forKey: ForelightSettings.appIntensityEnabledKey) as? [String: Bool]
        if let raw = defaults.dictionary(forKey: ForelightSettings.displayIntensitiesKey) {
            document.displayIntensities = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        document.displayDimmingDisabled = defaults.dictionary(forKey: ForelightSettings.displayDimmingDisabledKey) as? [String: Bool]
        if let data = defaults.data(forKey: ForelightSettings.focusGroupsKey) {
            document.focusGroups = try? JSONDecoder().decode([FocusGroup].self, from: data)
        }

        return document
    }

    func write(to defaults: UserDefaults) {
        if let isEnabled {
            defaults.set(isEnabled, forKey: ForelightSettings.enabledKey)
        }
        if let intensity {
            defaults.set(intensity, forKey: ForelightSettings.intensityKey)
        }
        if let hideWhileMoving {
            defaults.set(hideWhileMoving, forKey: ForelightSettings.hideWhileMovingKey)
        }
        if let fadeDuration {
            defaults.set(fadeDuration, forKey: ForelightSettings.fadeDurationKey)
        }
        if let restoreDelay {
            defaults.set(restoreDelay, forKey: ForelightSettings.restoreDelayKey)
        }
        if let appearanceMode {
            defaults.set(appearanceMode, forKey: ForelightSettings.appearanceModeKey)
        }
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: ForelightSettings.shortcutKey)
        }
        if let exceptions {
            defaults.set(exceptions, forKey: ForelightSettings.exceptionsKey)
        }
        if let appIntensities {
            defaults.set(appIntensities, forKey: ForelightSettings.appIntensitiesKey)
        }
        if let appIntensityEnabled {
            defaults.set(appIntensityEnabled, forKey: ForelightSettings.appIntensityEnabledKey)
        }
        if let displayIntensities {
            defaults.set(displayIntensities, forKey: ForelightSettings.displayIntensitiesKey)
        }
        if let displayDimmingDisabled {
            defaults.set(displayDimmingDisabled, forKey: ForelightSettings.displayDimmingDisabledKey)
        }
        if let focusGroups, let data = try? JSONEncoder().encode(focusGroups) {
            defaults.set(data, forKey: ForelightSettings.focusGroupsKey)
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> SettingsDocument {
        try JSONDecoder().decode(SettingsDocument.self, from: data)
    }
}
