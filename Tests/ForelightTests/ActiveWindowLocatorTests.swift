import CoreGraphics
import Foundation
import Testing
@testable import Forelight

struct ActiveWindowLocatorTests {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func window(
        pid: pid_t,
        layer: Int = 0,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        name: String? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            "kCGWindowOwnerPID": pid,
            "kCGWindowLayer": layer,
            "kCGWindowBounds": ["X": x, "Y": y, "Width": width, "Height": height] as NSDictionary
        ]
        if let name {
            info["kCGWindowOwnerName"] = name
        }
        return info
    }

    @Test func prefersPreferredOwner() {
        let list = [
            window(pid: 1, x: 0, y: 0, width: 800, height: 600),
            window(pid: 2, x: 100, y: 100, width: 400, height: 300)
        ]
        let found = ActiveWindowLocator.frontmostWindow(
            in: list,
            displayBounds: display,
            excluding: 999,
            preferredOwnerPID: 2
        )
        #expect(found?.bounds == CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    @Test func fallsBackToFirstFrontWindow() {
        let list = [
            window(pid: 1, x: 0, y: 0, width: 800, height: 600),
            window(pid: 2, x: 0, y: 0, width: 400, height: 300)
        ]
        let found = ActiveWindowLocator.frontmostWindow(
            in: list,
            displayBounds: display,
            excluding: 999,
            preferredOwnerPID: 7
        )
        #expect(found?.bounds == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func ignoresOwnProcessNonZeroLayerAndTinyWindows() {
        let list = [
            window(pid: 999, x: 0, y: 0, width: 1600, height: 900),
            window(pid: 1, layer: 3, x: 0, y: 0, width: 1600, height: 900),
            window(pid: 2, x: 0, y: 0, width: 20, height: 20)
        ]
        let found = ActiveWindowLocator.frontmostWindow(
            in: list,
            displayBounds: display,
            excluding: 999,
            preferredOwnerPID: 0
        )
        #expect(found == nil)
    }

    @Test func ignoresWindowsOutsideDisplay() {
        let list = [window(pid: 1, x: 5000, y: 5000, width: 400, height: 300)]
        let found = ActiveWindowLocator.frontmostWindow(
            in: list,
            displayBounds: display,
            excluding: 999,
            preferredOwnerPID: 0
        )
        #expect(found == nil)
    }
}
