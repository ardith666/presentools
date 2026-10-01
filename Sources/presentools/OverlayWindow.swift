import AppKit

/// Transparent, click-through overlay covering one display.
@MainActor
final class OverlayWindow: NSWindow {
    let screenIdentifier: CGDirectDisplayID

    /// Must sit above an ordinary app window (level 0) but below the menu bar.
    ///
    /// `.screenSaver` (1000) looked like the safe "above everything" choice and
    /// it broke the status menu: verified with CGWindowListCopyWindowInfo, our
    /// windows were layer 1000 while `Menubar` is 24 and pop-up menus are 101,
    /// so the overlay covered both and clicking the status item did nothing.
    /// 20 clears the app window and stays under both.
    static let overlayLevel = NSWindow.Level(rawValue: 20)

    init(screen: NSScreen) {
        screenIdentifier = OverlayWindow.displayID(of: screen)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = Self.overlayLevel

        // Fullscreen presentation lives in its own Space. Without these the
        // overlay stays on the desktop Space and appears to work while being
        // invisible during the actual presentation.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        contentView = view

        // constrainFrameRect is the documented screen→window conversion. Setting
        // screen.frame directly mis-places windows on a secondary display that
        // sits above or left of the primary one (negative Y origin).
        setFrame(constrainFrameRect(screen.frame, to: screen), display: true)
        orderFrontRegardless()
    }

    var overlayView: OverlayView { contentView as! OverlayView }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// `cursor` is already in this window's flipped view coordinates.
    func setEffect(_ effect: Effect, cursor: CGPoint) {
        overlayView.update(effect: effect, cursor: cursor)
    }
}

/// Flipped so its coordinates run top-left down, which is what the spotlight
/// radius and laser dot expect to measure from.
@MainActor
final class OverlayView: NSView {
    override var isFlipped: Bool { true }

    private var effect: Effect = .none
    private(set) var cursorInView: CGPoint = .zero
    private(set) var updateCount = 0

    func update(effect: Effect, cursor: CGPoint) {
        self.effect = effect
        cursorInView = cursor
        updateCount += 1
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        effect.draw(in: self, cursor: cursorInView)
    }
}
