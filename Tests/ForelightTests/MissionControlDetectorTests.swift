import CoreGraphics
import Foundation
import Testing
@testable import Forelight

struct MissionControlDetectorTests {
    private let screen = CGSize(width: 1920, height: 1080)
    private let dockPID: pid_t = 100

    private func window(
        ownerPID: pid_t,
        ownerName: String? = nil,
        x: Double = 0,
        y: Double = 0,
        width: Double,
        height: Double
    ) -> [String: Any] {
        var info: [String: Any] = [
            "kCGWindowOwnerPID": ownerPID,
            "kCGWindowLayer": 0,
            "kCGWindowBounds": ["X": x, "Y": y, "Width": width, "Height": height] as NSDictionary
        ]
        if let ownerName {
            info["kCGWindowOwnerName"] = ownerName
        }
        return info
    }

    @Test func inactiveWithoutScreens() {
        let list = [window(ownerPID: dockPID, width: 1920, height: 1080)]
        #expect(!MissionControlDetector.isActive(in: list, screenSizes: [], dockPID: dockPID))
    }

    @Test func inactiveWithNoWindows() {
        #expect(!MissionControlDetector.isActive(in: [], screenSizes: [screen], dockPID: dockPID))
    }

    @Test func activeWhenDockWindowCoversScreen() {
        let list = [window(ownerPID: dockPID, width: 1920, height: 1080)]
        #expect(MissionControlDetector.isActive(in: list, screenSizes: [screen], dockPID: dockPID))
    }

    @Test func activeWhenDockIdentifiedByName() {
        let list = [window(ownerPID: 999, ownerName: "Dock", width: 1920, height: 1080)]
        #expect(MissionControlDetector.isActive(in: list, screenSizes: [screen], dockPID: dockPID))
    }

    @Test func inactiveForNonDockFullscreenWindow() {
        let list = [window(ownerPID: 200, ownerName: "Safari", width: 1920, height: 1080)]
        #expect(!MissionControlDetector.isActive(in: list, screenSizes: [screen], dockPID: dockPID))
    }

    @Test func inactiveForDockWindowThatDoesNotCoverScreen() {
        let list = [window(ownerPID: dockPID, width: 1920, height: 40)]
        #expect(!MissionControlDetector.isActive(in: list, screenSizes: [screen], dockPID: dockPID))
    }

    @Test func matchesAnyConnectedScreen() {
        let portrait = CGSize(width: 1080, height: 1920)
        let list = [window(ownerPID: dockPID, x: 1470, y: -1395, width: 1080, height: 1920)]
        #expect(MissionControlDetector.isActive(in: list, screenSizes: [screen, portrait], dockPID: dockPID))
    }
}
