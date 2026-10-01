import AppKit
import Carbon

/// User-tunable look for all three effects, persisted in UserDefaults.
///
/// One store rather than a `Look` enum of constants: every value here is
/// something the user is expected to change, so a constant was the wrong
/// shape. Defaults match the values that shipped in 0.1.0, so an existing
/// install looks identical until something is actually touched.
@MainActor
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let spotlightRadius = "spotlightRadius"
        static let spotlightDim = "spotlightDim"
        static let laserRadius = "laserRadius"
        static let laserColor = "laserColor"
        static let lensSide = "lensSide"
        static let lensMagnification = "lensMagnification"
        static let ringColor = "ringColor"
        static let ringWidth = "ringWidth"
        static let autoUpdate = "autoUpdate"
        static let hasSeenLaunchAtLoginPrompt = "hasSeenLaunchAtLoginPrompt"

        static func hotKeyKeyCode(_ id: BindingID) -> String { "hotkey.\(id.storageSuffix).keyCode" }
        static func hotKeyModifiers(_ id: BindingID) -> String { "hotkey.\(id.storageSuffix).modifiers" }
        static func hotKeyMode(_ id: BindingID) -> String { "hotkey.\(id.storageSuffix).mode" }
    }

    private let defaults: UserDefaults

    /// The shipped 0.1.0 values. Every property initialiser and `reset()` reads
    /// these, so the defaults cannot drift apart.
    enum Default {
        static let spotlightRadius: CGFloat = 190
        static let spotlightDim: CGFloat = 0.82
        static let laserRadius: CGFloat = 9
        static let laserColor = NSColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
        static let lensSide: CGFloat = 460
        static let lensMagnification: CGFloat = 2
        static let ringColor: NSColor = .white
        static let ringWidth: CGFloat = 3
        static let autoUpdate = true
    }

    /// Fired after any value changes so the overlay can redraw immediately
    /// instead of waiting for the next cursor move.
    var onChange: (() -> Void)?

    // MARK: Spotlight

    /// Radius of the lit circle in points. Wide enough to read a line of body
    /// text without covering the sentence being discussed.
    var spotlightRadius: CGFloat = Default.spotlightRadius {
        didSet { persist(Key.spotlightRadius, spotlightRadius) }
    }

    /// How dark the surround goes, 0...1. Not fully opaque black by default:
    /// the audience should still read the shape of the slide, just not the
    /// fine detail.
    var spotlightDim: CGFloat = Default.spotlightDim {
        didSet { persist(Key.spotlightDim, spotlightDim) }
    }

    // MARK: Laser

    var laserRadius: CGFloat = Default.laserRadius {
        didSet { persist(Key.laserRadius, laserRadius) }
    }

    var laserColor: NSColor = Default.laserColor {
        didSet { persist(Key.laserColor, laserColor.hexString) }
    }

    /// Glow around the dot. Scaled from the radius so a bigger dot does not
    /// end up with a disproportionately large halo.
    var laserGlow: CGFloat { laserRadius * 3 }

    // MARK: Zoom

    /// Diameter of the lens in points.
    var lensSide: CGFloat = Default.lensSide {
        didSet { persist(Key.lensSide, lensSide) }
    }

    var lensMagnification: CGFloat = Default.lensMagnification {
        didSet { persist(Key.lensMagnification, lensMagnification) }
    }

    // MARK: Ring

    /// Edge colour for the spotlight and the lens. Both sit over slide content
    /// the user does not control, so a fixed colour disappears against some
    /// slides — yellow reads on dark, cyan on light.
    var ringColor: NSColor = .white {
        didSet { persist(Key.ringColor, ringColor.hexString) }
    }

    var ringWidth: CGFloat = 3 {
        didSet { persist(Key.ringWidth, ringWidth) }
    }

    // MARK: Updates + login item

    /// Whether to check for a newer release at launch. Off means no launch-time
    /// network traffic at all; the manual "Check for Updates…" item still works.
    var autoUpdate: Bool = Default.autoUpdate {
        didSet { persist(Key.autoUpdate, autoUpdate) }
    }

    /// Whether the one-shot login-item question has already been answered.
    ///
    /// Deliberately NOT reset by `reset()`: the prompt is asked once per
    /// install, not once per configuration, so a user who answered "Not Now"
    /// and later resets their look settings must not be asked again.
    var hasSeenLaunchAtLoginPrompt: Bool = false {
        didSet { persist(Key.hasSeenLaunchAtLoginPrompt, hasSeenLaunchAtLoginPrompt) }
    }

    /// Presets offered in the menu. Chosen to stay distinguishable on both
    /// light and dark slides rather than to span the whole wheel.
    static let ringPresets: [(name: String, color: NSColor)] = [
        ("White", .white),
        ("Yellow", NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)),
        ("Cyan", NSColor(red: 0.3, green: 0.9, blue: 1, alpha: 1)),
        ("Red", NSColor(red: 1, green: 0.25, blue: 0.25, alpha: 1)),
        ("Green", NSColor(red: 0.3, green: 1, blue: 0.45, alpha: 1)),
    ]

    static let laserPresets: [(name: String, color: NSColor)] = [
        ("Red", NSColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)),
        ("Yellow", NSColor(red: 1, green: 0.9, blue: 0.1, alpha: 1)),
        ("Green", NSColor(red: 0.2, green: 1, blue: 0.35, alpha: 1)),
        ("Cyan", NSColor(red: 0.2, green: 0.9, blue: 1, alpha: 1)),
        ("Magenta", NSColor(red: 1, green: 0.3, blue: 0.9, alpha: 1)),
        ("White", .white),
    ]

    // MARK: Menu titles

    /// Compact, unit-carrying labels so the menu reads as a value list rather
    /// than a list of opaque numbers.
    static func points(_ v: CGFloat) -> String { "\(Int(v)) pt" }

    // MARK: Load

    /// `defaults` is injected rather than hard-wired so `--selftest` can prove
    /// persistence against a throwaway suite. The default keeps every runtime
    /// call site on `Settings.shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let v = defaults.object(forKey: Key.spotlightRadius) as? Double { spotlightRadius = v }
        if let v = defaults.object(forKey: Key.spotlightDim) as? Double { spotlightDim = v }
        if let v = defaults.object(forKey: Key.laserRadius) as? Double { laserRadius = v }
        if let v = defaults.object(forKey: Key.lensSide) as? Double { lensSide = v }
        if let v = defaults.object(forKey: Key.lensMagnification) as? Double { lensMagnification = v }
        if let v = defaults.object(forKey: Key.ringWidth) as? Double { ringWidth = v }
        if let hex = defaults.string(forKey: Key.laserColor) { laserColor = NSColor(hex: hex) ?? laserColor }
        if let hex = defaults.string(forKey: Key.ringColor) { ringColor = NSColor(hex: hex) ?? ringColor }
        if defaults.object(forKey: Key.autoUpdate) != nil {
            autoUpdate = defaults.bool(forKey: Key.autoUpdate)
        }
        hasSeenLaunchAtLoginPrompt = defaults.bool(forKey: Key.hasSeenLaunchAtLoginPrompt)
    }

    // MARK: Hotkeys

    /// The shipped bindings, reachable for callers that need to diff against
    /// them. Unused today: the conflict rules that consume it land in a later
    /// task, so do not read this as dead code.
    var hotKeyDefaults: [BindingID: EffectBinding] { HotKeyBinding.Defaults.bindings }

    /// The live binding table.
    ///
    /// Read through a computed property rather than cached at launch so a record
    /// written by an older build, a partially written one, or a mode string this
    /// build does not know degrades to the shipped default for *that binding
    /// only*. Falling back wholesale would silently undo a user's other
    /// choices; skipping the fallback would leave an effect with no key that can
    /// switch it on.
    ///
    /// A missing or unrecognised mode means the *shipped* default for that
    /// binding, never a mode invented here and never "reject the record".
    /// `HotKeyDecision` reads a nil mode as `.hold` in both `onPress` and
    /// `onRelease`; anything else and a mode-less binding latches its effect
    /// and the release never clears it. Panic's mode is genuinely nil, and its
    /// own default is nil, so the two paths agree there by construction.
    ///
    /// Panic's `mode == nil` round-trips as nil because the mode key is simply
    /// not written: nil is that binding's real answer, not absent data.
    var hotKeyBindings: [BindingID: EffectBinding] {
        get {
            var table = HotKeyBinding.Defaults.bindings
            for id in BindingID.all {
                guard let keyCode = defaults.object(forKey: Key.hotKeyKeyCode(id)) as? Int,
                      let modifiers = defaults.object(forKey: Key.hotKeyModifiers(id)) as? Int
                else { continue }
                guard Self.isPlausible(id, keyCode: keyCode, modifiers: modifiers) else { continue }

                var mode = HotKeyBinding.Defaults.bindings[id]?.mode
                if let raw = defaults.string(forKey: Key.hotKeyMode(id)) {
                    // An unrecognised mode string falls back to the shipped
                    // default, same as an absent one. Hardcoding a mode here
                    // instead would make this the one place the shipped
                    // defaults cannot change.
                    mode = ActivationMode(rawValue: raw) ?? mode
                }
                table[id] = EffectBinding(
                    key: HotKeyBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers)),
                    mode: mode
                )
            }
            return table
        }
        set {
            for id in BindingID.all {
                guard let binding = newValue[id] else {
                    // A cleared binding leaves no key behind, so the getter falls
                    // back to the shipped default rather than reading a stale record.
                    defaults.removeObject(forKey: Key.hotKeyKeyCode(id))
                    defaults.removeObject(forKey: Key.hotKeyModifiers(id))
                    defaults.removeObject(forKey: Key.hotKeyMode(id))
                    continue
                }
                persist(Key.hotKeyKeyCode(id), Int(binding.key.keyCode))
                persist(Key.hotKeyModifiers(id), Int(binding.key.modifiers))
                if let mode = binding.mode {
                    persist(Key.hotKeyMode(id), mode.rawValue)
                } else {
                    defaults.removeObject(forKey: Key.hotKeyMode(id))
                }
            }
        }
    }

    /// Whether a record read off disk is safe to register.
    ///
    /// This lives on load rather than at registration because
    /// `RegisterEventHotKey` validates nothing, and a record arrives from disk
    /// before anything has a chance to object. Rebind-time validation only
    /// covers records this build wrote, so a corrupt or truncated record would
    /// otherwise reach Carbon unchecked.
    ///
    /// The goal is rejecting garbage from a corrupt record, not exhaustively
    /// validating every key: the check is deliberately cheap and conservative,
    /// and anything it lets through is still a key code the user themselves
    /// picked through the rebinding UI.
    private static func isPlausible(_ id: BindingID, keyCode: Int, modifiers: Int) -> Bool {
        let required: UInt32 = UInt32(cmdKey) | UInt32(optionKey)
        // An effect with neither cmd nor option captures a bare global
        // keystroke, so the app would swallow a plain keypress app-wide while the
        // user is typing. Panic is exempt: bare modifier is a deliberate choice
        // there, so a bare Esc stays legal.
        if id != .panic && (UInt32(modifiers) & required) == 0 { return false }
        // Real Carbon virtual key codes live in the ANSI/function range, well
        // under 0x80. Anything outside that came from a bad write, not a key.
        return keyCode > 0 && keyCode < 0x7F
    }

    /// Read-modify-write goes through here for the look settings so `onChange`
    /// cannot be forgotten at a call site. `hotKeyBindings` is the exception: it
    /// has its own setter that deliberately does not notify, and re-registering
    /// the Carbon hot keys is the caller's explicit job.
    func set<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>, _ value: T) {
        self[keyPath: keyPath] = value
        onChange?()
    }

    /// Every value back to the shipped default.
    ///
    /// The `onChange?()` at the end reaches `settingsChanged()` in `main.swift`,
    /// which re-frames the lens and repaints the overlays — but does *not*
    /// re-register Carbon hot keys. Whoever wires the runtime hot key path has
    /// to handle re-registration explicitly; do not assume this notification
    /// covers it.
    func reset() {
        spotlightRadius = Default.spotlightRadius
        spotlightDim = Default.spotlightDim
        laserRadius = Default.laserRadius
        laserColor = Default.laserColor
        lensSide = Default.lensSide
        lensMagnification = Default.lensMagnification
        ringColor = Default.ringColor
        ringWidth = Default.ringWidth
        hotKeyBindings = HotKeyBinding.Defaults.bindings
        autoUpdate = Default.autoUpdate
        onChange?()
    }

    private func persist(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }
}

extension NSColor {
    /// Round-trips through hex so colours survive a relaunch. Alpha is
    /// dropped deliberately: every colour here is opaque.
    ///
    /// `usingColorSpace` first, always. `.white` and `.black` are tagged-pointer
    /// catalog colours in Generic Gray Gamma 2.2, which has no RGB components,
    /// so reading `redComponent` off one raises `NSInvalidArgumentException`
    /// rather than returning a value.
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}
