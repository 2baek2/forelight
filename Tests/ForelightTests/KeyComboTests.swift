import AppKit
import Testing
@testable import Forelight

struct KeyComboTests {
    @Test func defaultDisplaysOptionCommandF() {
        #expect(KeyCombo.default.display == "⌥⌘F")
    }

    @Test func displaysModifiersInCanonicalOrder() {
        let modifiers = NSEvent.ModifierFlags([.command, .shift, .option, .control])
        let combo = KeyCombo(keyCode: 40, modifiers: modifiers.rawValue, keyEquivalent: "k")
        #expect(combo.display == "⌃⌥⇧⌘K")
    }

    @Test func mapsSpecialKeys() {
        #expect(KeyCombo.keyLabel(for: 49, keyEquivalent: " ") == "Space")
        #expect(KeyCombo.keyLabel(for: 36, keyEquivalent: "\r") == "↩")
        #expect(KeyCombo.keyLabel(for: 123, keyEquivalent: "") == "←")
        #expect(KeyCombo.keyLabel(for: 96, keyEquivalent: "") == "F5")
    }

    @Test func fallsBackToUppercasedKeyEquivalent() {
        #expect(KeyCombo.keyLabel(for: 0, keyEquivalent: "a") == "A")
        #expect(KeyCombo.keyLabel(for: 0, keyEquivalent: "") == "?")
    }

    @Test func roundTripsThroughCodable() throws {
        let combo = KeyCombo(keyCode: 8, modifiers: 1_048_576, keyEquivalent: "c")
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        #expect(decoded == combo)
    }
}
