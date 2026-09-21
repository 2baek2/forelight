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
}
