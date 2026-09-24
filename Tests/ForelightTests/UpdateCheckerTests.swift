import Testing
@testable import Forelight

struct UpdateCheckerTests {
    @Test func normalizesTags() {
        #expect(UpdateChecker.normalizedVersion("v0.1.0") == "0.1.0")
        #expect(UpdateChecker.normalizedVersion("1.2.3") == "1.2.3")
        #expect(UpdateChecker.normalizedVersion(" V2.0 ") == "2.0")
        #expect(UpdateChecker.normalizedVersion("nightly") == nil)
        #expect(UpdateChecker.normalizedVersion("v1.x") == nil)
        #expect(UpdateChecker.normalizedVersion("") == nil)
    }

    @Test func comparesVersions() {
        #expect(UpdateChecker.isNewer("0.2.0", than: "0.1.0"))
        #expect(UpdateChecker.isNewer("0.1.1", than: "0.1.0"))
        #expect(UpdateChecker.isNewer("0.1.0.1", than: "0.1.0"))
        #expect(!UpdateChecker.isNewer("0.1.0", than: "0.1.0"))
        #expect(!UpdateChecker.isNewer("0.0.9", than: "0.1.0"))
        #expect(UpdateChecker.isNewer("1.0", than: "0.9.9"))
    }

    @Test func compareTreatsMissingComponentsAsZero() {
        #expect(UpdateChecker.compare("1", "1.0.0") == .orderedSame)
        #expect(UpdateChecker.compare("1.0.1", "1") == .orderedDescending)
        #expect(UpdateChecker.compare("0.9", "0.10") == .orderedAscending)
    }
}
