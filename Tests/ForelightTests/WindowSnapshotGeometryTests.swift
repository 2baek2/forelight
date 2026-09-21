import CoreGraphics
import Testing
@testable import Forelight

struct WindowSnapshotGeometryTests {
    private let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func convertsWithinDisplayAtOrigin() {
        let frame = WindowSnapshot.cocoaFrame(
            quartzBounds: CGRect(x: 100, y: 50, width: 400, height: 300),
            quartzDisplayBounds: displayBounds,
            screenFrame: displayBounds
        )
        #expect(frame == CGRect(x: 100, y: 730, width: 400, height: 300))
    }

    @Test func offsetsByScreenOrigin() {
        let frame = WindowSnapshot.cocoaFrame(
            quartzBounds: CGRect(x: 2000, y: 100, width: 300, height: 200),
            quartzDisplayBounds: CGRect(x: 1920, y: 0, width: 1280, height: 800),
            screenFrame: CGRect(x: 1920, y: 0, width: 1280, height: 800)
        )
        #expect(frame == CGRect(x: 2000, y: 500, width: 300, height: 200))
    }

    @Test func clipsToDisplay() {
        let frame = WindowSnapshot.cocoaFrame(
            quartzBounds: CGRect(x: -100, y: 0, width: 300, height: 200),
            quartzDisplayBounds: displayBounds,
            screenFrame: displayBounds
        )
        #expect(frame == CGRect(x: 0, y: 880, width: 200, height: 200))
    }

    @Test func returnsNilWhenNoIntersection() {
        let frame = WindowSnapshot.cocoaFrame(
            quartzBounds: CGRect(x: 5000, y: 5000, width: 100, height: 100),
            quartzDisplayBounds: displayBounds,
            screenFrame: displayBounds
        )
        #expect(frame == nil)
    }
}
