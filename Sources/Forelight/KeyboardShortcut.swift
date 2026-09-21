import AppKit
import SwiftUI

struct KeyCombo: Equatable, Codable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt
    var keyEquivalent: String

    static let `default` = KeyCombo(
        keyCode: 3,
        modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue,
        keyEquivalent: "f"
    )

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var display: String {
        var result = ""
        let flags = modifierFlags
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += Self.keyLabel(for: keyCode, keyEquivalent: keyEquivalent)
        return result
    }

    static func keyLabel(for keyCode: UInt16, keyEquivalent: String) -> String {
        if let special = specialKeys[keyCode] { return special }
        return keyEquivalent.isEmpty ? "?" : keyEquivalent.uppercased()
    }

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}

struct ShortcutRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    let onChange: (KeyCombo) -> Void
    let onRecordingChanged: (Bool) -> Void
    var onClear: (() -> Void)? = nil

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.combo = combo
        view.onCapture = onChange
        view.onRecordingChanged = onRecordingChanged
        view.onClear = onClear
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.combo = combo
        nsView.onRecordingChanged = onRecordingChanged
        nsView.onClear = onClear
        nsView.needsDisplay = true
    }
}

/// Lets the global shortcut handler ignore keys while a new shortcut is being
/// recorded, without needing main-actor hops inside the event monitor.
final class ShortcutGate {
    private let lock = NSLock()
    private var suppressed = false

    func setSuppressed(_ value: Bool) {
        lock.lock()
        suppressed = value
        lock.unlock()
    }

    var isSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suppressed
    }
}

final class ShortcutRecorderView: NSView {
    var combo: KeyCombo?
    var onCapture: ((KeyCombo) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onClear: (() -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Press keys…"
        } else if let combo {
            text = combo.display
        } else {
            text = "Record"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        setRecording(true)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Delete clears the shortcut.
        if event.keyCode == 51 {
            onClear?()
            setRecording(false)
            window?.makeFirstResponder(nil)
            return
        }

        // Escape cancels recording.
        guard event.keyCode != 53 else {
            setRecording(false)
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // A shortcut needs at least one modifier so a plain key press does not
        // hijack every keystroke system-wide.
        guard !modifiers.isEmpty else { return }

        let combo = KeyCombo(
            keyCode: event.keyCode,
            modifiers: modifiers.rawValue,
            keyEquivalent: event.charactersIgnoringModifiers ?? ""
        )
        onCapture?(combo)
        setRecording(false)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        setRecording(false)
        return super.resignFirstResponder()
    }

    private func setRecording(_ value: Bool) {
        isRecording = value
        onRecordingChanged?(value)
        needsDisplay = true
    }
}
