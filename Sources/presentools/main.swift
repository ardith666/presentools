import AppKit
import ScreenCaptureKit

// Presentools — 3 presentation effects as a transparent overlay above whatever
// app is on screen. No presentation app is inspected, imported, or controlled.
//
//   ⌥0 no effect   ⌥1 spotlight   ⌥2 laser   ⌥3 zoom   ⌥Esc all off
//
// Spotlight and laser need no permission. Zoom needs Screen Recording; without
// it the other two still work.
//
//   --effect=spotlight   start in that effect (used for visual verification)
//   --selftest           render effects to a bitmap and check pixel values, then exit

let selftestMode = CommandLine.arguments.contains("--selftest")
let menuTestMode = CommandLine.arguments.contains("--menutest")
let requestedEffect = CommandLine.arguments
    .first { $0.hasPrefix("--effect=") }
    .map { String($0.dropFirst("--effect=".count)) }
    .flatMap(Effect.init(rawValue:)) ?? .none

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // tray-only: no Dock icon, no launch window

@MainActor
final class Presentools: NSObject, NSApplicationDelegate {
    private var overlays: [OverlayWindow] = []
    private var poller: CursorPoller?
    private var hotkeys: HotKeyCenter?
    /// Held so the recorder window is not torn down the moment `openShortcutRecorder`
    /// returns. `isReleasedWhenClosed` keeps the window itself alive after closing.
    private var recorder: ShortcutRecorderWindow?
    /// Same reason, for the settings panel.
    private var settingsWindow: SettingsWindow?
    private var lens: ZoomLens?
    private var statusItem: NSStatusItem?

    private(set) var effect: Effect = .none
    /// The display the cursor is on. Effects are drawn only there; a second
    /// monitor stays untouched so the audience there is not watching a mask.
    private(set) var activeScreen: NSScreen?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if selftestMode {
            let ok = SelfTest.run()
            fflush(stdout)
            exit(ok ? 0 : 1)
        }
        overlays = NSScreen.screens.map(OverlayWindow.init(screen:))
        lens = ZoomLens()
        // Without this a new radius only shows on the next cursor move, and
        // "Larger" appears to do nothing while the pointer rests.
        Settings.shared.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        poller = CursorPoller(hz: 60) { [weak self] cursor in
            MainActor.assumeIsolated { self?.onCursorMove(cursor) }
        }
        hotkeys = HotKeyCenter(
            onPress: { [weak self] id in
                MainActor.assumeIsolated { self?.handleHotKeyPress(id) }
            },
            onRelease: { [weak self] id, duration in
                MainActor.assumeIsolated { self?.handleHotKeyRelease(id, duration: duration) }
            }
        )
        // Read through Settings so a rebind made in the recorder survives a relaunch.
        let registration = hotkeys?.start(bindings: bindings()) ?? [:]
        reportRegistration(registration)
        // "Something got registered", not "all of it did": a combination another
        // app owns is a per-binding failure, and the rest still work.
        let registered = registration.values.contains(true)

        setUpStatusItem()
        if menuTestMode {
            runMenuTest()
            return
        }
        set(requestedEffect)
        report(registered: registered)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.reportAfterTicks()
        }
        // The first ScreenCaptureKit call is slow, so the 2s report can still
        // show zero captures. Re-report once the lens has had time to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            self?.reportAfterTicks(label: "t+7s")
        }
        // First-run login prompt + optional auto-update check
        if !Settings.shared.hasSeenLaunchAtLoginPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = "Launch Presentools at login?"
                alert.informativeText = "Presentools can start automatically when you log in."
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "Not Now")
                if alert.runModal() == .alertFirstButtonReturn {
                    do { try LaunchAtLogin.setEnabled(true) } catch {}
                }
                Settings.shared.hasSeenLaunchAtLoginPrompt = true
                self.rebuildMenu()
            }
        }
        if Settings.shared.autoUpdate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                UpdateChecker().check { outcome in
                    DispatchQueue.main.async {
                        switch outcome {
                        case .newerAvailable(let tag, _, let assetURL, let digest):
                            if let assetURL { self.presentUpdateAvailable(tag: tag, assetURL: assetURL, digest: digest) }
                        default: break
                        }
                    }
                }
            }
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Presentools"
        )
        rebuildMenu()
    }

    /// Rebuilt on every change so the checkmark always matches the live effect.
    private func rebuildMenu() {
        let menu = NSMenu()
        for candidate in [Effect.none, .spotlight, .laser, .zoom] {
            let item = NSMenuItem(
                title: candidate.title,
                action: #selector(pickEffect(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Effect.allCases.firstIndex(of: candidate) ?? 0
            item.state = candidate == effect ? .on : .off
            if candidate == .zoom, !lens!.permissionGranted {
                item.title = "\(candidate.title) — needs Screen Recording"
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let shortcuts = NSMenuItem(
            title: "Shortcuts…", action: #selector(openShortcutRecorder(_:)), keyEquivalent: ""
        )
        shortcuts.target = self
        menu.addItem(shortcuts)
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())
        // Auto-update toggle
        let autoUpdateItem = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleAutoUpdate(_:)), keyEquivalent: "")
        autoUpdateItem.target = self
        autoUpdateItem.state = Settings.shared.autoUpdate ? .on : .off
        menu.addItem(autoUpdateItem)
        // Check now
        let checkNow = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesNow(_:)), keyEquivalent: "")
        checkNow.target = self
        menu.addItem(checkNow)
        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        switch LaunchAtLogin.status() {
        case .enabled: loginItem.state = .on
        case .notRegistered: loginItem.state = .off
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let perm = NSMenuItem(
            title: lens?.permissionGranted == true ? "Screen Recording: granted" : "Grant Screen Recording…",
            action: #selector(grantPermission(_:)), keyEquivalent: ""
        )
        perm.target = self
        perm.isEnabled = lens?.permissionGranted != true
        menu.addItem(perm)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About", action: nil, keyEquivalent: "")
        let aboutMenu = NSMenu()
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let vitem = NSMenuItem(title: "Version \(ver)", action: nil, keyEquivalent: "")
        vitem.isEnabled = false
        aboutMenu.addItem(vitem)
        let repo = NSMenuItem(title: "ardith666/presentools", action: #selector(openRepo(_:)), keyEquivalent: "")
        repo.target = self
        aboutMenu.addItem(repo)
        about.submenu = aboutMenu
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Presentools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = app
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    /// One item, not four submenus. The values live in a panel with real sliders:
    /// an `NSMenu` cannot host an interactive slider, and reaching one number
    /// three levels deep is the problem the panel replaces. `Reset to Defaults`
    /// moved there too, so the menu bar stays a list of actions.
    private func addSettings(to menu: NSMenu) {
        let item = NSMenuItem(
            title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
    }

    @objc private func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(
                currentEffect: { [weak self] in self?.effect ?? .none },
                setEffect: { [weak self] next in self?.set(next) },
                resetAll: { [weak self] in self?.resetSettings(nil) }
            )
        }
        settingsWindow?.show()
    }

    @objc private func resetSettings(_ sender: Any?) {
        Settings.shared.reset()
        // `reset()` also restores the binding table, so the Carbon registrations
        // have to be redone from the new table. Without this the stored defaults
        // and the live hotkeys disagree until the next launch.
        hotkeys?.stop()
        reportRegistration(hotkeys?.start(bindings: bindings()) ?? [:])
        rebuildMenu()
    }

    /// A setting changed: re-frame the lens and repaint every overlay now.
    private func settingsChanged() {
        lens?.applySize()
        lens?.viewNeedsDisplay = true
        for overlay in overlays { overlay.overlayView.needsDisplay = true }
    }

    @objc private func pickEffect(_ sender: NSMenuItem) {
        set(Effect.allCases[sender.tag])
    }

    @objc private func grantPermission(_ sender: Any?) {
        lens?.requestPermission()
        rebuildMenu()
        report()
    }

    func set(_ next: Effect) {
        if next.needsScreenRecording && !(lens?.permissionGranted ?? false) {
            lens?.requestPermission()
        }
        effect = next
        if next != .zoom { lens?.hide() }
        // Force one frame so the new effect shows on every display immediately,
        // instead of waiting for the next cursor move.
        for overlay in overlays { overlay.overlayView.needsDisplay = true }
        rebuildMenu()
        report()
    }

    // MARK: Hotkeys

    /// The live binding table, read from `Settings` rather than from the shipped
    /// defaults, so a rebind survives a relaunch. `hotKeyBindings` already falls
    /// back per-binding to the default when a stored value is missing or
    /// malformed, so this is safe to call on every key event.
    private func bindings() -> [BindingID: EffectBinding] {
        Settings.shared.hotKeyBindings
    }

    /// The stored activation mode. A missing or malformed entry arrives as `nil`,
    /// which `HotKeyDecision` reads as the shipped default (`.hold`); that layer is
    /// the only place the rule is applied, so it is not duplicated here.
    private func mode(for id: BindingID) -> ActivationMode? {
        bindings()[id]?.mode
    }

    private func handleHotKeyPress(_ id: BindingID) {
        set(HotKeyDecision.onPress(id, mode: mode(for: id), current: effect))
    }

    @objc private func openShortcutRecorder(_ sender: Any?) {
        // The global hotkeys must be unregistered while the window is open, or
        // recording ⌥1 fires Spotlight instead of being recorded. This is the one
        // non-obvious requirement in the feature.
        hotkeys?.stop()
        recorder?.releaseWindow()
        recorder = ShortcutRecorderWindow(bindings: bindings()) { [weak self] table in
            guard let self else { return }
            Settings.shared.hotKeyBindings = table
            let result = self.hotkeys?.start(bindings: table) ?? [:]
            self.reportRegistration(result)
            Settings.shared.onChange?()
        }
        recorder?.show()
    }

    /// A combination another app already owns fails to register silently, so say
    /// which one. `say`, not `print`: stdout is block-buffered when redirected to
    /// a log file, and a dropped line is the only evidence the user gets that a
    /// binding did not take.
    private func reportRegistration(_ result: [BindingID: Bool]) {
        for id in BindingID.all where result[id] == false {
            say("shortcut for \(id.title) is owned by another app and did not register")
        }
    }

    private func handleHotKeyRelease(_ id: BindingID, duration: TimeInterval) {
        // `nil` is "change nothing" — a toggle's release, a tap, or a panic
        // release — and is not the same answer as `Effect.none`, "turn it all
        // off". Unwrapping here keeps the two apart; the decision layer has
        // already chosen which one this is.
        guard let next = HotKeyDecision.onRelease(id, mode: mode(for: id), duration: duration) else {
            return
        }
        set(next)
    }

    private func onCursorMove(_ cursor: NSPoint) {
        let screens = NSScreen.screens
        let screen = screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? screens.first
        guard let screen else { return }
        activeScreen = screen
        let id = OverlayWindow.displayID(of: screen)
        for overlay in overlays {
            let owns = overlay.screenIdentifier == id
            overlay.setEffect(owns ? effect : .none, cursor: overlay.overlayView.convert(cursor, from: nil))
        }
        if effect == .zoom, let lens {
            lens.tick(cursorInScreen: cursor, screen: screen)
        }
    }

    private func say(_ line: String) {
        print(line)
        fflush(stdout)  // stdout is block-buffered when redirected to a file
    }

    private func report(registered: Bool? = nil) {
        if let registered {
            say("hotkeys: \(hotkeys?.registeredCount ?? 0)/\(BindingID.all.count) registered (ok=\(registered))")
        }
        say("effect: \(effect.rawValue)  overlayWindows: \(overlays.count)")
        say("screenRecording: \(lens?.permissionGranted ?? false)  lensCaptures: \(lens?.captureCount ?? 0)")
        if let err = lens?.lastError { say("lensError: \(err)") }
        reportStatusItem()
        probeShareableContent()
    }

    /// Separates the two causes of "clicking does nothing", which look
    /// identical from the outside:
    ///   1. the menu is broken  -> `performClick` also fails to show it
    ///   2. the click is eaten  -> `performClick` shows it fine
    /// `performClick` raises the menu with no mouse involved at all, so it
    /// isolates menu construction from event delivery.
    private func runMenuTest() {
        guard let item = statusItem, let btn = item.button else {
            say("menuTest: FATAL no status item"); exit(1)
        }
        say("menuTest: button frame=\(btn.frame) hidden=\(btn.isHidden) enabled=\(btn.isEnabled)")
        say("menuTest: overlaysIgnoreMouse=\(self.overlays.map { $0.ignoresMouseEvents })")
        say("menuTest: window=\(btn.window.map { "\($0.frame) visible=\($0.isVisible) onActiveSpace=\($0.isOnActiveSpace) layer=\($0.level.rawValue)" } ?? "NIL")")
        say("menuTest: menu assigned=\(item.menu != nil) items=\(item.menu?.items.count ?? -1)")
        say("menuTest: topLevel=\((item.menu?.items ?? []).map(\.title))")
        for entry in (item.menu?.items ?? []) where entry.submenu != nil {
            say("menuTest: submenu '\(entry.title)' enabled=\(entry.isEnabled) items=\(entry.submenu!.items.count)")
            say("menuTest:   children=\(entry.submenu!.items.map(\.title))")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Drive `mouseDown` directly, not `performClick`. The status bar
            // button pops its menu by overriding `mouseDown`, and `performClick`
            // skips straight to the action, so it reported "MENU DID NOT OPEN"
            // even with a fully built menu.
            if let ev = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: btn.bounds.midX, y: btn.bounds.midY),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: btn.window?.windowNumber ?? 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) {
                self.say("menuTest: driving mouseDown at \(ev.locationInWindow)")
                btn.mouseDown(with: ev)
            }
            // No follow-up block on purpose: a menu that opens puts the app into
            // its modal tracking loop, so nothing after mouseDown runs. If this
            // line prints, the menu did NOT open. That single fact is what
            // separates "menu is broken" from "click is eaten".
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.say("menuTest: VERDICT=MENU DID NOT OPEN (reached code after mouseDown)")
                exit(0)
            }
        }
    }

    /// Why the status item would not open. Two failure modes look identical
    /// from the outside — "clicking does nothing":
    ///   1. no button on screen at all (creation failed)
    ///   2. a button that opens an EMPTY menu (build failed)
    /// So print the button geometry, the window state, and the built menu.
    private func reportStatusItem() {
        guard let item = statusItem else { say("statusItem: NIL (never created)"); return }
        guard let btn = item.button else { say("statusItem: button NIL"); return }
        let win = btn.window
        say("statusButton: frame=\(btn.frame) hidden=\(btn.isHidden) enabled=\(btn.isEnabled)")
        say("statusWindow: level=\(win?.level.rawValue ?? -1) visible=\(win?.isVisible ?? false) onActiveSpace=\(win?.isOnActiveSpace ?? false)")
        say("statusMenu: items=\(item.menu?.items.count ?? -1) titles=\((item.menu?.items ?? []).map(\.title))")
        say("windows: count=\(NSApp.windows.count) policy=\(NSApp.activationPolicy().rawValue)")
    }

    /// Unit 1 saw `0 display(s)` from a bare SwiftPM binary and blamed the
    /// missing bundle identity. Verify that claim instead of asserting it.
    // MARK: - Update + About

    @objc private func openRepo(_ sender: Any?) {
        if let url = URL(string: "https://github.com/ardith666/presentools") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleAutoUpdate(_ sender: NSMenuItem) {
        Settings.shared.autoUpdate.toggle()
        sender.state = Settings.shared.autoUpdate ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            let st = LaunchAtLogin.status()
            try LaunchAtLogin.setEnabled(st != .enabled)
        } catch {
            say("launchAtLogin: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func checkForUpdatesNow(_ sender: Any?) {
        UpdateChecker().check { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case .newerAvailable(let tag, _, let assetURL, let digest):
                    self.presentUpdateAvailable(tag: tag, assetURL: assetURL, digest: digest)
                case .upToDate, .failed:
                    break
                }
            }
        }
    }

    private func presentUpdateAvailable(tag: String, assetURL: URL?, digest: String?) {
        guard let assetURL else { return }
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Presentools \(tag) is available. Download DMG and drag to Applications (running app will not be replaced)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            UpdateChecker().downloadAndOpenFolder(assetURL: assetURL, expectedDigest: digest) { _ in }
        }
    }

    private func probeShareableContent() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                let sizes = content.displays.map { "\($0.width)x\($0.height)" }.joined(separator: " ")
                say("sckDisplays: \(content.displays.count) [\(sizes)]")
            } catch {
                say("sckDisplays: error \(error.localizedDescription)")
            }
        }
    }

    private func reportAfterTicks(label: String = "t+2s") {
        say("\(label) polls: \(poller?.tickCount ?? 0) (expect >=120 in 2s)  drawnFrames: \(overlays.map { String($0.overlayView.updateCount) }.joined(separator: ","))")
        say("\(label) lens: captures=\(lens?.captureCount ?? 0) permission=\(lens?.permissionGranted ?? false) error=\(lens?.lastError ?? "none")")
        // Captured pixels vs points tells us the display's real scale. On a
        // retina display a 230pt rect must return 460px. On a 1x display it
        // correctly returns 230px and the lens magnifies by point-doubling,
        // which is the hardware limit, not a bug.
        if let size = lens?.lastImagePixels, size.width > 0 {
            let s = Settings.shared
            let captured = s.lensSide / s.lensMagnification
            let backing = size.width / captured
            say("\(label) lensImage: \(Int(size.width))x\(Int(size.height))px for a \(Int(captured))pt rect (backingScale=\(String(format: "%.1f", backing)))")
        }
        if let overlay = overlays.first {
            let c = overlay.overlayView.cursorInView
            say("\(label) cursorInOverlay0: \(Int(c.x)),\(Int(c.y))  overlaySize: \(Int(overlay.overlayView.bounds.width))x\(Int(overlay.overlayView.bounds.height))")
        }
    }
}

let delegate = Presentools()
app.delegate = delegate
app.run()
