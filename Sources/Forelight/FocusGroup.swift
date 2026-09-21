import Foundation

/// A saved snapshot of the dimming configuration. Applying a group restores the
/// global intensity, the exception list, and every per-app intensity override.
struct FocusGroup: Identifiable, Codable, Equatable {
    var name: String
    var intensity: Double
    var exceptions: [String: Bool]
    var appIntensities: [String: Double]
    var appIntensityEnabled: [String: Bool]

    var id: String { name }
}
