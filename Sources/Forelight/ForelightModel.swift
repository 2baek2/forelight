import Combine

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

    init(
        isEnabled: Bool,
        currentApplicationName: String?,
        currentApplicationIsExcluded: Bool,
        accessibilityTrusted: Bool,
        intensity: Double,
        hideWhileMoving: Bool,
        fadeDuration: Double,
        restoreDelay: Double
    ) {
        self.isEnabled = isEnabled
        self.currentApplicationName = currentApplicationName
        self.currentApplicationIsExcluded = currentApplicationIsExcluded
        self.accessibilityTrusted = accessibilityTrusted
        self.intensity = intensity
        self.hideWhileMoving = hideWhileMoving
        self.fadeDuration = fadeDuration
        self.restoreDelay = restoreDelay
    }
}
