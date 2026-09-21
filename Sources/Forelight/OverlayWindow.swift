import AppKit

final class OverlayWindow: NSWindow {
    let targetScreen: NSScreen
    private let overlayView: OverlayView
    private var visibilityAnimationID = 0

    init(screen: NSScreen) {
        targetScreen = screen
        overlayView = OverlayView(frame: screen.frame)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = overlayView
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayWindow does not support storyboard decoding")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(cutout: CGRect?, alpha: Double) {
        overlayView.cutout = cutout.map { convertToLocalCoordinates($0) }
        overlayView.alpha = alpha
        overlayView.needsDisplay = true
    }

    func fadeOut(duration: TimeInterval) {
        visibilityAnimationID += 1
        let animationID = visibilityAnimationID

        guard duration > 0 else {
            hideImmediately()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.visibilityAnimationID == animationID else { return }
                self.orderOut(nil)
            }
        }
    }

    func fadeIn(duration: TimeInterval) {
        visibilityAnimationID += 1
        orderFrontRegardless()

        guard duration > 0 else {
            alphaValue = 1
            return
        }

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        }
    }

    func hideImmediately() {
        visibilityAnimationID += 1
        alphaValue = 0
        orderOut(nil)
    }

    func restoreImmediately() {
        visibilityAnimationID += 1
        alphaValue = 1
        if !isVisible {
            orderFrontRegardless()
        }
    }

    private func convertToLocalCoordinates(_ globalFrame: CGRect) -> CGRect {
        globalFrame.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
    }
}

final class OverlayView: NSView {
    var cutout: CGRect?
    var alpha: Double = 0.45

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let overlayPath = NSBezierPath(rect: bounds)
        if let cutout {
            let safeCutout = cutout.intersection(bounds)
            if !safeCutout.isNull, !safeCutout.isEmpty {
                overlayPath.append(
                    NSBezierPath(
                        roundedRect: safeCutout.insetBy(dx: -2, dy: -2),
                        xRadius: 8,
                        yRadius: 8
                    )
                )
                overlayPath.windingRule = .evenOdd
            }
        }

        NSColor.black.withAlphaComponent(alpha).setFill()
        overlayPath.fill()
    }
}
