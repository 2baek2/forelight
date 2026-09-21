import Foundation
import Testing
@testable import Forelight

struct FocusGroupTests {
    @Test func roundTripsThroughCodable() throws {
        let group = FocusGroup(
            name: "Coding",
            intensity: 0.4,
            exceptions: ["com.apple.dt.Xcode": true],
            appIntensities: ["com.apple.dt.Xcode": 0.3],
            appIntensityEnabled: ["com.apple.dt.Xcode": true],
            spotlightMode: .windowAndCursor,
            spotlightRadius: 140,
            spotlightFeather: 30,
            displayIntensities: ["display-uuid": 0.6],
            displayDimmingDisabled: ["other-display": true],
            shortcut: .default
        )
        let data = try JSONEncoder().encode([group])
        let decoded = try JSONDecoder().decode([FocusGroup].self, from: data)
        #expect(decoded == [group])
    }

    @Test func identifiedByName() {
        let group = FocusGroup(
            name: "Writing",
            intensity: 0.6,
            exceptions: [:],
            appIntensities: [:],
            appIntensityEnabled: [:]
        )
        #expect(group.id == "Writing")
    }
}
