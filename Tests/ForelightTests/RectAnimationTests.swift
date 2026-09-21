import CoreGraphics
import Testing
@testable import Forelight

struct RectAnimationTests {
    private let from = CGRect(x: 0, y: 0, width: 10, height: 10)
    private let to = CGRect(x: 100, y: 50, width: 30, height: 20)

    @Test func returnsEndpoints() {
        #expect(RectAnimation.lerp(from, to, progress: 0) == from)
        #expect(RectAnimation.lerp(from, to, progress: 1) == to)
    }

    @Test func lerpsMidpoint() {
        #expect(RectAnimation.lerp(from, to, progress: 0.5) == CGRect(x: 50, y: 25, width: 20, height: 15))
    }

    @Test func clampsProgress() {
        #expect(RectAnimation.lerp(from, to, progress: -1) == from)
        #expect(RectAnimation.lerp(from, to, progress: 2) == to)
    }
}
