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
    var vignette: Double

    static let `default` = DimStyle(cornerRadius: 8, padding: 2, tint: .black, vignette: 0)
}

struct Spotlight {
    var center: CGPoint
    var radius: CGFloat
    var feather: CGFloat
}

enum RectAnimation {
    static func lerp(_ from: CGRect, _ to: CGRect, progress: Double) -> CGRect {
        let t = min(max(progress, 0), 1)
        return CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * t,
            y: from.origin.y + (to.origin.y - from.origin.y) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
    }
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

    func update(cutouts: [CGRect], alpha: Double, style: DimStyle, animationDuration: TimeInterval) {
        overlayView.alpha = alpha
        overlayView.style = style
        overlayView.setCutouts(
            cutouts.map { convertToLocalCoordinates($0) },
            animationDuration: animationDuration
        )
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
    var alpha: Double = 0.45 {
        didSet { needsDisplay = true }
    }

    var style: DimStyle = .default {
        didSet { needsDisplay = true }
    }

    private(set) var spotlight: Spotlight?

    private var displayedCutouts: [CGRect] = []
    private var cutoutTimer: Timer?
    private var cutoutAnimationStart = Date.distantPast
    private var cutoutFrom: [CGRect] = []
    private var cutoutTo: [CGRect] = []
    private var cutoutDuration: TimeInterval = 0

    override var isOpaque: Bool { false }

    /// Updates the window cutouts, optionally morphing from the previous ones.
    func setCutouts(_ rects: [CGRect], animationDuration: TimeInterval) {
        if animationDuration <= 0 || displayedCutouts.count != rects.count || displayedCutouts == rects {
            stopCutoutAnimation()
            displayedCutouts = rects
            needsDisplay = true
            return
        }

        cutoutFrom = displayedCutouts
        cutoutTo = rects
        cutoutDuration = animationDuration
        cutoutAnimationStart = Date()
        startCutoutAnimationIfNeeded()
    }

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

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let overlayPath = NSBezierPath(rect: bounds)
        for cutout in displayedCutouts {
            let safeCutout = cutout.intersection(bounds)
            guard !safeCutout.isNull, !safeCutout.isEmpty else { continue }
            overlayPath.append(cutoutPath(for: safeCutout))
            overlayPath.windingRule = .evenOdd
        }

        if style.vignette > 0 {
            // Extra dim at the edges first, then keep the cutouts clear.
            drawVignette(in: context)
            clearCutouts(in: context)
        }

        style.tint.color.withAlphaComponent(alpha).setFill()
        overlayPath.fill()

        if let spotlight, spotlight.radius > 0 {
            punchFeatheredHole(spotlight, in: context)
        }
    }

    // MARK: - Drawing helpers

    private func cutoutPath(for rect: CGRect) -> NSBezierPath {
        NSBezierPath(
            roundedRect: rect.insetBy(dx: -style.padding, dy: -style.padding),
            xRadius: style.cornerRadius,
            yRadius: style.cornerRadius
        )
    }

    private func drawVignette(in context: CGContext) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(hypot(bounds.width, bounds.height) / 2, 1)
        let colors = [
            style.tint.color.withAlphaComponent(0).cgColor,
            style.tint.color.withAlphaComponent(style.vignette).cgColor
        ] as CFArray

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) else {
            return
        }

        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: radius * 0.35,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }

    /// Clears the vignette (and anything else) inside the cutouts so they stay
    /// fully transparent.
    private func clearCutouts(in context: CGContext) {
        context.setBlendMode(.destinationOut)
        defer { context.setBlendMode(.normal) }

        for cutout in displayedCutouts {
            let safeCutout = cutout.intersection(bounds)
            guard !safeCutout.isNull, !safeCutout.isEmpty else { continue }
            cutoutPath(for: safeCutout).fill()
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

    // MARK: - Cutout animation

    private func startCutoutAnimationIfNeeded() {
        guard cutoutTimer == nil else { return }
        cutoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepCutoutAnimation()
            }
        }
    }

    private func stepCutoutAnimation() {
        let elapsed = Date().timeIntervalSince(cutoutAnimationStart)
        let progress = cutoutDuration > 0 ? min(max(elapsed / cutoutDuration, 0), 1) : 1
        let eased = 1 - pow(1 - progress, 3)

        displayedCutouts = zip(cutoutFrom, cutoutTo).map {
            RectAnimation.lerp($0, $1, progress: eased)
        }
        needsDisplay = true

        if progress >= 1 {
            stopCutoutAnimation()
            displayedCutouts = cutoutTo
            needsDisplay = true
        }
    }

    private func stopCutoutAnimation() {
        cutoutTimer?.invalidate()
        cutoutTimer = nil
    }
}
