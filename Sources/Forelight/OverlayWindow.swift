import AppKit

enum SpotlightMode: String, CaseIterable, Codable, Identifiable {
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

enum DimTint: String, CaseIterable, Identifiable {
    case black
    case warm
    case cool

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: return "Black"
        case .warm: return "Warm"
        case .cool: return "Cool"
        }
    }

    var color: NSColor {
        switch self {
        case .black: return .black
        case .warm: return NSColor(srgbRed: 0.11, green: 0.05, blue: 0.0, alpha: 1)
        case .cool: return NSColor(srgbRed: 0.0, green: 0.02, blue: 0.11, alpha: 1)
        }
    }
}

struct DimStyle {
    var cornerRadius: CGFloat
    var padding: CGFloat
    var tint: DimTint

    static let `default` = DimStyle(cornerRadius: 8, padding: 2, tint: .black)
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

    func update(cutout: CGRect?, alpha: Double, style: DimStyle) {
        overlayView.cutout = cutout.map { convertToLocalCoordinates($0) }
        overlayView.alpha = alpha
        overlayView.style = style
        overlayView.needsDisplay = true
    }

    func updateSpotlight(globalCenter: CGPoint, radius: CGFloat, feather: CGFloat) {
        guard frame.contains(globalCenter) else {
            overlayView.setSpotlight(nil)
            return
        }
        let local = CGPoint(
            x: globalCenter.x - frame.origin.x,
            y: globalCenter.y - frame.origin.y
        )
        overlayView.setSpotlight(Spotlight(center: local, radius: radius, feather: feather))
    }

    func clearSpotlight() {
        overlayView.setSpotlight(nil)
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
    var style: DimStyle = .default
    private(set) var spotlight: Spotlight?

    override var isOpaque: Bool { false }

    /// Updates the cursor spotlight and invalidates only the affected region so
    /// moving the pointer does not redraw the whole screen.
    func setSpotlight(_ newValue: Spotlight?) {
        let oldRect = spotlightDirtyRect(for: spotlight)
        let newRect = spotlightDirtyRect(for: newValue)
        spotlight = newValue

        switch (oldRect, newRect) {
        case (nil, nil):
            return
        case let (old?, nil):
            setNeedsDisplay(old)
        case let (nil, new?):
            setNeedsDisplay(new)
        case let (old?, new?):
            setNeedsDisplay(old.union(new))
        }
    }

    private func spotlightDirtyRect(for spotlight: Spotlight?) -> CGRect? {
        guard let spotlight, spotlight.radius > 0 else { return nil }
        let margin = spotlight.radius + 2
        let rect = CGRect(
            x: spotlight.center.x - margin,
            y: spotlight.center.y - margin,
            width: margin * 2,
            height: margin * 2
        )
        let clipped = rect.intersection(bounds)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

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
                        roundedRect: safeCutout.insetBy(dx: -style.padding, dy: -style.padding),
                        xRadius: style.cornerRadius,
                        yRadius: style.cornerRadius
                    )
                )
                overlayPath.windingRule = .evenOdd
            }
        }

        style.tint.color.withAlphaComponent(alpha).setFill()
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

        let opaque = style.tint.color.withAlphaComponent(1).cgColor
        let clear = style.tint.color.withAlphaComponent(0).cgColor
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
