import AppKit
import CoreGraphics

struct WindowSnapshot {
    let bounds: CGRect
}

extension WindowSnapshot {
    func cocoaFrame(on screen: NSScreen) -> CGRect? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return Self.cocoaFrame(
            quartzBounds: bounds,
            quartzDisplayBounds: CGDisplayBounds(displayID),
            screenFrame: screen.frame
        )
    }

    /// Converts a Quartz (top-left origin) window rect into the Cocoa
    /// (bottom-left origin) space of a display. Pure so it can be unit tested.
    static func cocoaFrame(
        quartzBounds: CGRect,
        quartzDisplayBounds: CGRect,
        screenFrame: CGRect
    ) -> CGRect? {
        let intersection = quartzBounds.intersection(quartzDisplayBounds)
        guard !intersection.isNull, !intersection.isEmpty else { return nil }

        let cocoaX = screenFrame.origin.x + (intersection.origin.x - quartzDisplayBounds.origin.x)
        let cocoaY = screenFrame.origin.y + (quartzDisplayBounds.maxY - intersection.maxY)
        return CGRect(
            x: cocoaX,
            y: cocoaY,
            width: intersection.width,
            height: intersection.height
        )
    }
}

enum ActiveWindowLocator {
    static func frontmostWindow(
        on screen: NSScreen,
        excluding ownPID: pid_t,
        preferredOwnerPID: pid_t
    ) -> WindowSnapshot? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return frontmostWindow(
            in: windowList,
            displayBounds: CGDisplayBounds(displayID),
            excluding: ownPID,
            preferredOwnerPID: preferredOwnerPID
        )
    }

    /// Pure, front-to-back selection over a window list so it can be tested
    /// with a synthetic list instead of a live window server.
    static func frontmostWindow(
        in windowList: [[String: Any]],
        displayBounds: CGRect,
        excluding ownPID: pid_t,
        preferredOwnerPID: pid_t
    ) -> WindowSnapshot? {
        var fallback: WindowSnapshot?
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  !isComputerUseHelper(ownerPID: ownerPID, info: info),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width > 30,
                  bounds.height > 30,
                  bounds.intersects(displayBounds) else {
                continue
            }

            let snapshot = WindowSnapshot(bounds: bounds)
            if ownerPID == preferredOwnerPID {
                return snapshot
            }
            fallback = fallback ?? snapshot
        }

        return fallback
    }

    private static func isComputerUseHelper(ownerPID: pid_t, info: [String: Any]) -> Bool {
        let ownerName = info[kCGWindowOwnerName as String] as? String
        return ownerName?.localizedCaseInsensitiveContains("Computer Use") == true
            || NSRunningApplication(processIdentifier: ownerPID)?.localizedName?.localizedCaseInsensitiveContains("Computer Use") == true
    }
}
