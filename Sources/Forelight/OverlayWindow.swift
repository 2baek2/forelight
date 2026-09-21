import AppKit

enum SpotlightMode: String, CaseIterable, Identifiable {
    case window
    case cursor
    case windowAndCursor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .window: return "Window"
        case .cursor: return "Cursor"
        case .windowAndCursor: return "Window + Cursor"
        }
    }

    var includesWindow: Bool { self != .cursor }
    var includesCursor: Bool { self != .window }
}

struct Spotlight {
    var center: CGPoint
    var radius: CGFloat
    var feather: CGFloat
}

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
        // Keep the dim layer out of screen recordings and screen shares.
        sharingType = .none
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

    func updateSpotlight(globalCenter: CGPoint, radius: CGFloat, feather: CGFloat) {
        guard frame.contains(globalCenter) else {
            clearSpotlight()
            return
        }
        let local = CGPoint(
            x: globalCenter.x - frame.origin.x,
            y: globalCenter.y - frame.origin.y
        )
        overlayView.spotlight = Spotlight(center: local, radius: radius, feather: feather)
        overlayView.needsDisplay = true
    }

    func clearSpotlight() {
        guard overlayView.spotlight != nil else { return }
        overlayView.spotlight = nil
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
    var spotlight: Spotlight?

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

        if let spotlight, spotlight.radius > 0 {
            punchFeatheredHole(spotlight, in: context)
        }
    }

    /// Removes the dim around the cursor with a soft edge by drawing a radial
    /// gradient in destination-out mode: fully clear out to the inner radius,
    /// then fading to nothing at the outer radius.
    private func punchFeatheredHole(_ spotlight: Spotlight, in context: CGContext) {
        let radius = max(spotlight.radius, 1)
        let circle = CGRect(
            x: spotlight.center.x - radius,
            y: spotlight.center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.setBlendMode(.destinationOut)
        defer { context.setBlendMode(.normal) }

        guard spotlight.feather > 0 else {
            context.fillEllipse(in: circle)
            return
        }

        let inner = min(max(radius - spotlight.feather, 0), radius)
        let solidStop = min(max(inner / radius, 0), 0.999)

        let opaque = NSColor.black.withAlphaComponent(1).cgColor
        let clear = NSColor.black.withAlphaComponent(0).cgColor
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [opaque, opaque, clear] as CFArray,
            locations: [0, solidStop, 1]
        ) else {
            return
        }

        context.drawRadialGradient(
            gradient,
            startCenter: spotlight.center,
            startRadius: 0,
            endCenter: spotlight.center,
            endRadius: radius,
            options: []
        )
    }
}
