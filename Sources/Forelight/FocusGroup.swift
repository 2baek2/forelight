import Foundation

/// A saved snapshot of the dimming configuration. Applying a group restores the
/// global intensity, the exception list, every per-app intensity override, the
/// display settings, and the cursor spotlight.
struct FocusGroup: Identifiable, Codable, Equatable {
    var name: String
    var intensity: Double
    var exceptions: [String: Bool]
    var appIntensities: [String: Double]
    var appIntensityEnabled: [String: Bool]
    var spotlightMode: SpotlightMode? = nil
    var spotlightRadius: Double? = nil
    var spotlightFeather: Double? = nil
    var displayIntensities: [String: Double]? = nil
    var displayDimmingDisabled: [String: Bool]? = nil
    var shortcut: KeyCombo? = nil

    var id: String { name }
}
