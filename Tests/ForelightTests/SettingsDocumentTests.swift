import Foundation
import Testing
@testable import Forelight

struct SettingsDocumentTests {
    @Test func roundTripsThroughJSON() throws {
        var document = SettingsDocument()
        document.isEnabled = false
        document.intensity = 0.4
        document.hideWhileMoving = true
        document.appearanceMode = "light"
        document.shortcut = .default
        document.exceptions = ["com.apple.Safari": true]
        document.appIntensities = ["com.apple.dt.Xcode": 0.3]
        document.appIntensityEnabled = ["com.apple.dt.Xcode": false]
        document.displayIntensities = ["display-uuid": 0.8]
        document.displayDimmingDisabled = ["other-display": true]
        document.spotlightMode = "windowAndCursor"
        document.spotlightRadius = 140
        document.spotlightFeather = 30
        document.cutoutRadius = 12
        document.cutoutPadding = 6
        document.dimTint = "warm"
        document.focusGroups = [
            FocusGroup(name: "Coding", intensity: 0.4, exceptions: [:], appIntensities: [:], appIntensityEnabled: [:])
        ]

        let data = try document.encoded()
        let decoded = try SettingsDocument.decode(from: data)
        #expect(decoded == document)
    }

    @Test func writesAndLoadsThroughDefaults() {
        let suite = "com.forelight.settingsdocument.test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        var document = SettingsDocument()
        document.isEnabled = true
        document.intensity = 0.55
        document.exceptions = ["com.apple.Safari": false]
        document.appIntensities = ["com.apple.Notes": 0.7]
        document.write(to: defaults)

        let loaded = SettingsDocument.load(from: defaults)
        #expect(loaded.isEnabled == true)
        #expect(loaded.intensity == 0.55)
        #expect(loaded.exceptions == ["com.apple.Safari": false])
        #expect(loaded.appIntensities == ["com.apple.Notes": 0.7])

        defaults.removePersistentDomain(forName: suite)
    }
}
