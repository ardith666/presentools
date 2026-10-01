import AppKit
import ScreenCaptureKit

/// A magnifier window that follows the cursor.
///
/// Uses `SCScreenshotManager.captureImage(in:)`, which grabs exactly one rect at
/// native resolution. The `captureImage(contentFilter:configuration:)` path
/// instead resized the whole display down to the window size — a miniature, not
/// a magnification, because nothing was cropped.
///
/// Re-captures on a throttle rather than streaming: a slide is static, so a new
/// frame is only worth taking a few times a second.
@MainActor
final class ZoomLens {
    /// Captures per second. The window itself still tracks the cursor at 60Hz.
    static let captureHz: Double = 8

    /// `captureImage(in:)` documents the rect as "points on the screen space"
    /// but never says which corner the origin is. Top-left is the SCK
    /// convention used everywhere else in this framework, and it is what
    /// `SCContentFilter` source rects use, so both are kept consistent here.
    /// Unverified on a real slide — if the lens shows the wrong part of the
    /// screen, flip this one constant.
    static let rectOriginIsTopLeft = true

    private let window: NSWindow
    private let view: LensView
    private var pending = false
    private var lastCapture = Date.distantPast

    private(set) var captureCount = 0
    private(set) var lastError: String?
    private(set) var lastImagePixels = CGSize.zero
    private(set) var permissionGranted = CGPreflightScreenCaptureAccess()

    init() {
        let side = Settings.shared.lensSide
        view = LensView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        window = NSWindow(
            contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Same reason as OverlayWindow: at .screenSaver the lens would sit
        // above the menu bar and block the status menu.
        window.level = OverlayWindow.overlayLevel
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.orderFrontRegardless()
        window.alphaValue = 0
    }

    func requestPermission() {
        if !permissionGranted { permissionGranted = CGRequestScreenCaptureAccess() }
    }

    /// Called on every cursor poll; captures only when the throttle allows, and
    /// otherwise just moves the window so it tracks the pointer at 60Hz.
    func tick(cursorInScreen: CGPoint, screen: NSScreen) {
        guard permissionGranted else { return }
        let due = Date().timeIntervalSince(lastCapture) >= 1.0 / Self.captureHz
        if due && !pending {
            lastCapture = Date()
            pending = true
            capture(cursor: cursorInScreen, screen: screen)
        } else {
            moveOnly(cursorInScreen: cursorInScreen, screen: screen)
        }
    }

    /// Re-frames the window after a size change in Settings. Called on every
    /// settings change, so it has to be a no-op when nothing moved.
    func applySize() {
        let side = Settings.shared.lensSide
        guard abs(window.frame.width - side) > 0.5 else { return }
        view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        window.setContentSize(NSSize(width: side, height: side))
        view.needsDisplay = true
    }

    /// Sit the lens below-right of the cursor, flipping at the screen edge so it
    /// never pushes the magnified content off screen.
    private func moveOnly(cursorInScreen: CGPoint, screen: NSScreen) {
        let f = screen.frame
        let side = Settings.shared.lensSide
        var origin = CGPoint(x: cursorInScreen.x + 36, y: cursorInScreen.y - 36 - side)
        if origin.x + side > f.maxX { origin.x = cursorInScreen.x - 36 - side }
        if origin.y < f.minY { origin.y = cursorInScreen.y + 36 }
        window.setFrameOrigin(CGPoint(
            x: min(max(origin.x, f.minX), f.maxX - side),
            y: min(max(origin.y, f.minY), f.maxY - side)
        ))
    }

    private func capture(cursor: CGPoint, screen: NSScreen) {
        let f = screen.frame
        // Grab only the on-screen area being magnified; the image comes back at
        // native pixel resolution, so a retina display already supplies the 2x.
        let side = Settings.shared.lensSide / Settings.shared.lensMagnification
        let localX = cursor.x - f.minX
        let localY = Self.rectOriginIsTopLeft ? f.maxY - cursor.y : cursor.y - f.minY
        let rect = CGRect(
            x: max(0, min(localX - side / 2, f.width - side)),
            y: max(0, min(localY - side / 2, f.height - side)),
            width: side, height: side
        )

        Task { [weak self] in
            guard let self else { return }
            defer { self.pending = false }
            do {
                let image = try await SCScreenshotManager.captureImage(in: rect)
                self.captureCount += 1
                self.lastError = nil
                self.lastImagePixels = CGSize(width: image.width, height: image.height)
                self.view.present(image)
                self.moveOnly(cursorInScreen: cursor, screen: screen)
                self.window.alphaValue = 1
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Exposed so a settings change can repaint without waiting for the next
    /// capture; the next tick refreshes the pixels anyway.
    var viewNeedsDisplay: Bool {
        get { view.needsDisplay }
        set { view.needsDisplay = newValue }
    }

    func hide() {
        window.alphaValue = 0
        view.clear()
    }
}

@MainActor
final class LensView: NSView {
    override var isFlipped: Bool { true }

    private var image: CGImage?

    func present(_ image: CGImage) {
        self.image = image
        needsDisplay = true
    }

    func clear() {
        image = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.width / 2
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)

        // Circle, not square: the user asked for a lens shape, and a square
        // window of magnified pixels reads as a broken window rather than a
        // tool. Clip rather than resize the window so hit geometry stays square.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(
            x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2
        ))
        ctx.clip()

        if let image {
            // CGImage rows run top-down while the view is flipped, so flip back
            // or the magnified content comes out upside down.
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: bounds)
        } else {
            NSColor.black.withAlphaComponent(0.25).setFill()
            bounds.fill()
        }
        ctx.restoreGState()

        // Ring on top so the edge stays visible over any slide content.
        let width = Settings.shared.ringWidth
        guard width > 0 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(Settings.shared.ringColor.cgColor)
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: CGRect(
            x: centre.x - r + width / 2, y: centre.y - r + width / 2,
            width: r * 2 - width, height: r * 2 - width
        ))
        ctx.restoreGState()
    }
}
