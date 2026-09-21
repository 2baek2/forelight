import AppKit
import CoreGraphics

/// A stable identifier for a connected display, plus its human readable name.
enum DisplayIdentifier {
    static func info(for screen: NSScreen) -> (id: String, name: String)? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        let identifier: String
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            identifier = string
        } else {
            identifier = "display-\(number)"
        }

        return (identifier, screen.localizedName)
    }
}
