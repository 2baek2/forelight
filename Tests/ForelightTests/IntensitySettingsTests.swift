import Testing
@testable import Forelight

struct IntensitySettingsTests {
    @Test func clampsBelowRange() {
        #expect(ForelightSettings.clampedIntensity(0.02) == 0.10)
    }

    @Test func clampsAboveRange() {
        #expect(ForelightSettings.clampedIntensity(0.95) == 0.90)
    }

    @Test func keepsValueInsideRange() {
        #expect(ForelightSettings.clampedIntensity(0.5) == 0.5)
        #expect(ForelightSettings.clampedIntensity(0.10) == 0.10)
        #expect(ForelightSettings.clampedIntensity(0.90) == 0.90)
    }

    @Test func enabledOverrideWins() {
        #expect(ForelightSettings.effectiveIntensity(global: 0.5, override: 0.2, isEnabled: true) == 0.2)
    }

    @Test func disabledOverrideFallsBackToGlobal() {
        #expect(ForelightSettings.effectiveIntensity(global: 0.5, override: 0.2, isEnabled: false) == 0.5)
    }

    @Test func missingOverrideUsesGlobal() {
        #expect(ForelightSettings.effectiveIntensity(global: 0.5, override: nil, isEnabled: true) == 0.5)
        #expect(ForelightSettings.effectiveIntensity(global: 0.5, override: nil, isEnabled: false) == 0.5)
    }

    @Test func displayOverrideWinsOverApp() {
        let resolved = ForelightSettings.resolvedIntensity(
            global: 0.5,
            appOverride: 0.2,
            appEnabled: true,
            displayOverride: 0.8
        )
        #expect(resolved == 0.8)
    }

    @Test func missingDisplayOverrideFallsBackToApp() {
        let resolved = ForelightSettings.resolvedIntensity(
            global: 0.5,
            appOverride: 0.2,
            appEnabled: true,
            displayOverride: nil
        )
        #expect(resolved == 0.2)
    }

    @Test func noOverridesUseGlobal() {
        let resolved = ForelightSettings.resolvedIntensity(
            global: 0.5,
            appOverride: nil,
            appEnabled: false,
            displayOverride: nil
        )
        #expect(resolved == 0.5)
    }
}
