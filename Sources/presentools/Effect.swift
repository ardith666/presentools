import AppKit

/// The one effect that is active. Presentation tools have a single pointer
/// behaviour at a time — Logitech's remote switches modes rather than stacking
/// them, and a mask under a magnifier is just a broken screen.
enum Effect: String, CaseIterable {
    case none
    case spotlight
    case laser
    case zoom

    var title: String {
        switch self {
        case .none: "No Effect"
        case .spotlight: "Spotlight"
        case .laser: "Laser Pointer"
        case .zoom: "Zoom Lens"
        }
    }

    /// Matches the digit in the global shortcut, so the menu teaches the key.
    var key: String {
        switch self {
        case .none: "0"
        case .spotlight: "1"
        case .laser: "2"
        case .zoom: "3"
        }
    }

    /// Zoom reads screen pixels, so it is the only effect the user can refuse.
    /// The other two need no permission at all.
    var needsScreenRecording: Bool { self == .zoom }
}

/// Live look values. `Settings.shared` is the single source: every one of these
/// is user-tunable, so a compile-time constant was the wrong shape.
///
/// Main-actor because the store is; every reader is already on the main actor
/// (view drawing and window management are main-actor isolated).
@MainActor
enum Look {
    static var spotlightRadius: CGFloat { Settings.shared.spotlightRadius }
    static var dimAlpha: CGFloat { Settings.shared.spotlightDim }
    static var ringColor: NSColor { Settings.shared.ringColor }
    static var ringWidth: CGFloat { Settings.shared.ringWidth }
}

/// Main-actor because it reads `NSView.bounds` and draws through
/// `NSGraphicsContext.current`; it is only ever called from `OverlayView.draw`.
@MainActor
extension Effect {
    /// Every effect draws on an already-cleared, fully transparent view.
    func draw(in view: NSView, cursor: CGPoint) {
        switch self {
        case .none, .zoom:
            // Zoom owns its own window, so there is nothing to paint here.
            break
        case .spotlight:
            drawSpotlight(in: view, cursor: cursor)
        case .laser:
            drawLaser(in: view, cursor: cursor)
        }
    }

    /// Dims everything except a hard-edged lit circle under the pointer.
    ///
    /// A radial gradient was the obvious first cut and it is the wrong shape
    /// for a spotlight: it never reaches full dim, so the screen corners stay
    /// readable and the effect loses its point. One even-odd fill gives a clean
    /// edge at any dim strength, and the edge is what makes the circle read as
    /// a circle.
    private func drawSpotlight(in view: NSView, cursor: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = view.bounds
        let r = Look.spotlightRadius

        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: CGRect(x: cursor.x - r, y: cursor.y - r, width: r * 2, height: r * 2))

        ctx.saveGState()
        // Clip first. An even-odd path paints any part of the circle that hangs
        // off the surface (one crossing = odd = filled), so near a screen edge
        // this would leave a stray blob.
        ctx.clip(to: bounds)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(Look.dimAlpha).cgColor)
        ctx.drawPath(using: .eoFill)
        ctx.restoreGState()

        // Ring on top: the user asked for a visible edge, and a hard edge that
        // is the same colour as a dark slide reads as no edge at all.
        guard Look.ringWidth > 0 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(Look.ringColor.cgColor)
        ctx.setLineWidth(Look.ringWidth)
        let half = Look.ringWidth / 2
        ctx.strokeEllipse(in: CGRect(
            x: cursor.x - r + half, y: cursor.y - r + half,
            width: r * 2 - Look.ringWidth, height: r * 2 - Look.ringWidth
        ))
        ctx.restoreGState()
    }

    /// A red dot that stays where it is put. No fading trail — that is the
    /// legacy laser behaviour, and it makes the point unreadable while moving.
    private func drawLaser(in view: NSView, cursor: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = Settings.shared
        ctx.saveGState()
        ctx.setFillColor(s.laserColor.cgColor)
        ctx.setShadow(offset: .zero, blur: s.laserGlow, color: s.laserColor.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: cursor.x - s.laserRadius, y: cursor.y - s.laserRadius,
            width: s.laserRadius * 2, height: s.laserRadius * 2
        ))
        ctx.restoreGState()
    }
}
