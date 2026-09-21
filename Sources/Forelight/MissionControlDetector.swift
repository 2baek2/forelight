import AppKit
import CoreGraphics

enum MissionControlDetector {
    /// Mission Control, App Exposé, Launchpad and Show Desktop are all drawn by
    /// the Dock as fullscreen windows. Detect those so the dim overlay can step
    /// aside while one of those system surfaces is open.
    static func isActive() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let screenSizes = NSScreen.screens.map { $0.frame.size }
        let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier

        return isActive(in: windowList, screenSizes: screenSizes, dockPID: dockPID)
    }

    /// Pure check over a window list so it can be tested without a live window
    /// server. A Dock-owned window that covers a whole display means one of the
    /// Dock's fullscreen surfaces is up.
    static func isActive(
        in windowList: [[String: Any]],
        screenSizes: [CGSize],
        dockPID: pid_t?
    ) -> Bool {
        guard !screenSizes.isEmpty else { return false }

        for info in windowList {
            let ownerName = info[kCGWindowOwnerName as String] as? String
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            let isDock = ownerName == "Dock" || (dockPID != nil && ownerPID == dockPID)
            guard isDock else { continue }

            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width > 0,
                  bounds.height > 0 else {
                continue
            }

            let coversScreen = screenSizes.contains { size in
                bounds.width >= size.width * 0.95 && bounds.height >= size.height * 0.95
            }
            if coversScreen {
                return true
            }
        }

        return false
    }
}
