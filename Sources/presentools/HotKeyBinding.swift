import AppKit
import Carbon

/// One physical key combination, as Carbon wants it. Stored separately from
/// `ActivationMode` so the "which key" and the "what it does" questions can be
/// changed independently.
struct HotKeyBinding: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Stable, readable form of a modifier mask, used only in diagnostics and
    /// tests. Carbon's `cmdKey` is `0x0100`, so hex alone would be unreadable.
    static func digest(_ modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("cmd") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("opt") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("ctrl") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    /// Carbon's modifier mask as AppKit reports it. Caps Lock and Fn are
    /// deliberately ignored: neither should change what a binding means.
    static func modifierMask(from event: NSEvent) -> UInt32 {
        var mask: UInt32 = 0
        if event.modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// Placeholder key for the modifier-only preview shown while a combination is
    /// being assembled. `A` is arbitrary: only the modifier glyphs are legible at
    /// that point, and a real letter reads better than `key 0` next to them.
    static let glyphPreviewKeyCode = UInt32(kVK_ANSI_A)
}

/// What a press does. Hold is momentary: the effect lives only while the key is
/// down. Toggle is sticky: the press flips it and the release does nothing.
enum ActivationMode: String, CaseIterable {
    case hold
    case toggle
}

/// Everything the user can rebind. The four effects are the pointer behaviours,
/// plus one panic binding that clears whatever is active.
enum BindingID: Hashable {
    case effect(Effect)
    case panic

    static var all: [BindingID] {
        Effect.allCases.map(BindingID.effect) + [.panic]
    }

    var title: String {
        switch self {
        case .effect(let effect): effect.title
        case .panic: "All Off"
        }
    }

    /// `UserDefaults` key fragment. The `effect.` prefix is here purely so the key
    /// reads as `effect.0` in a `UserDefaults` dump, where `Effect`'s bare digit
    /// on its own would be unreadable.
    ///
    /// This raw value is on-disk ABI: renaming a case orphans a user's saved
    /// binding, and reusing a raw value silently hands a new effect someone
    /// else's custom hot key. Both need a source edit plus a migration plan.
    var storageSuffix: String {
        switch self {
        case .effect(let effect): "effect.\(effect.rawValue)"
        case .panic: "panic"
        }
    }
}

struct EffectBinding: Equatable {
    var key: HotKeyBinding
    /// `nil` for the panic binding, which has no mode: it acts on press and
    /// ignores its release.
    var mode: ActivationMode?
}

extension HotKeyBinding {
    enum Defaults {
        /// ⌥ alone, no ⌘. A presenter reaching for the number row already has ⌥
        /// under the other hand; adding ⌘ makes a chord that is awkward one-handed
        /// and competes with app shortcuts. `HotKeyConflict.reason` still requires
        /// ⌘ or ⌥ on effects, so nothing weakens by dropping ⌘ here.
        private static let opt = UInt32(optionKey)

        /// kVK_ANSI_* are not contiguous: 1, 2, 3 are 0x12-0x14 but 0 is 0x1D.
        private static let digits: [(Effect, UInt32)] = [
            (.none, UInt32(kVK_ANSI_0)),
            (.spotlight, UInt32(kVK_ANSI_1)),
            (.laser, UInt32(kVK_ANSI_2)),
            (.zoom, UInt32(kVK_ANSI_3)),
        ]

        static let bindings: [BindingID: EffectBinding] = {
            var map: [BindingID: EffectBinding] = [:]
            for (effect, code) in digits {
                map[.effect(effect)] = EffectBinding(
                    key: HotKeyBinding(keyCode: code, modifiers: opt),
                    mode: .toggle
                )
            }
            // ⌥Esc rather than bare Esc. A zero-modifier binding is legal since
            // macOS 10.3, but it claims Esc from Keynote and PowerPoint, where
            // presenters need it to leave fullscreen. Exempt from the
            // modifier rule so a user who disagrees can still set it.
            map[.panic] = EffectBinding(
                key: HotKeyBinding(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey)),
                mode: nil
            )
            return map
        }()
    }
}

/// Why a candidate combination is refused. Returning `nil` means accept it.
/// Rejecting rather than warning is deliberate: a binding that silently does not
/// work is worse than one the user has to pick a second time.
///
/// Pure like `HotKeyDecision`, so `--selftest` can prove the whole matrix
/// without a running app, and so the recorder window has one place to ask.
enum HotKeyConflict {
    /// Common macOS shortcuts. Claiming one of these makes the app lose a key
    /// it needs, which is a much worse outcome than a narrower feature.
    private static let reserved: [(UInt32, UInt32)] = [
        (UInt32(kVK_Space), UInt32(cmdKey)),
        (UInt32(kVK_Space), UInt32(controlKey)),
        (UInt32(kVK_Tab), UInt32(cmdKey)),
        (UInt32(kVK_Tab), UInt32(optionKey)),
        (UInt32(kVK_ANSI_Q), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_W), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_H), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_M), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_E), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Comma), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Slash), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Equal), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Minus), UInt32(cmdKey)),
        (UInt32(kVK_ANSI_Grave), UInt32(cmdKey)),
    ]

    /// F1–F12 without ⌘ or ⌥ are hardware-level on most keyboards and are often
    /// already taken by the system. Listed rather than ranged: the codes are not
    /// contiguous (`F1` is 122 and `F12` is 111), so `kVK_F1...kVK_F12` is an
    /// invalid range and traps the moment it is built.
    private static let bareFunctionKeys: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
    ]

    private static func isUnqualifiedFunctionKey(_ keyCode: UInt32) -> Bool {
        bareFunctionKeys.contains(keyCode)
    }

    /// `nil` when the candidate is acceptable, otherwise a sentence naming the
    /// problem.
    ///
    /// A binding never conflicts with itself: `id` is skipped when scanning
    /// `table`, so re-picking a binding's current combination is accepted and a
    /// rejected edit can be retried without first undoing it. Whole
    /// combinations are compared, not key codes — `⌘1` is not `⌥1`.
    ///
    /// The caller passes the live table unchanged. `id` may or may not be in it.
    static func reason(
        for candidate: HotKeyBinding,
        id: BindingID,
        in table: [BindingID: EffectBinding]
    ) -> String? {
        for (otherID, other) in table where otherID != id {
            if other.key == candidate {
                return "Already used by \(otherID.title)."
            }
        }

        for (code, modifiers) in reserved where candidate == HotKeyBinding(keyCode: code, modifiers: modifiers) {
            return "\(describe(candidate)) is used by macOS — pick another."
        }

        // The panic key is the one binding allowed to be a bare key, because it
        // is the escape hatch a user reaches for when something is already
        // wrong. Effects have to stay clear of the keyboard.
        if case .panic = id {
            return nil
        }

        let hasCommandOrOption = candidate.modifiers & (UInt32(cmdKey) | UInt32(optionKey)) != 0
        if !hasCommandOrOption {
            if isUnqualifiedFunctionKey(candidate.keyCode) {
                return "F-keys need ⌘ or ⌥ — the system reserves bare ones."
            }
            return "\(describe(candidate)) has no ⌘ or ⌥, so it would fight the app you are presenting from."
        }
        return nil
    }

    /// Every key code this app can be asked to display, spelled out. Written as a
    /// flat table because Carbon's codes are laid out for the driver, not for
    /// arithmetic: letters run 0, 11, 8, 2, 14… and F-keys run 122, 120, 99, 118…
    /// so any `kVK_ANSI_A...kVK_ANSI_Z` range both traps (lower > upper) and covers
    /// the wrong keys. A key missing here renders as `key 57`, which still tells
    /// two bindings apart.
    private static let names: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Delete",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Backslash): "\\",
    ]

    /// Human-readable form, used only in rejection messages, where a message
    /// quoting a raw key code would be unreadable in a menu.
    static func describe(_ binding: HotKeyBinding) -> String {
        // Order follows the menu (⌘⌥, not Apple's ⌥⌘), so a binding
        // reads identically in the recorder and everywhere else.
        var parts: [String] = []
        if binding.modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if binding.modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if binding.modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if binding.modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        parts.append(keyName(binding.keyCode))
        return parts.joined()
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        names[keyCode] ?? "key \(keyCode)"
    }
}

/// Every question about what a key press means, answered with no Carbon and no
/// AppKit. Keeping it pure is what lets `--selftest` prove the whole matrix;
/// the runtime only has to measure a duration and call in here.
enum HotKeyDecision {
    /// Below this, a press-and-release is a tap. At or above, it is a hold.
    static let tapThreshold: TimeInterval = 0.25

    static func isHold(_ duration: TimeInterval) -> Bool {
        duration >= tapThreshold
    }

    /// Carbon re-delivers `kEventHotKeyPressed` while a key is held down.
    /// Applying it again would flicker toggle mode and restart the duration
    /// measurement, turning an intended hold into a tap. `HotKeyCenter` drops
    /// repeats before reaching here; this makes the contract explicit.
    static func onAutoRepeat(_ id: BindingID, _ mode: ActivationMode?) -> Effect? { nil }

    /// The effect that should be active after the key goes down.
    static func onPress(_ id: BindingID, mode: ActivationMode?, current: Effect) -> Effect {
        switch id {
        case .panic:
            return .none
        case .effect(let effect):
            // No stored mode yet means the shipped default, which is hold.
            switch mode ?? .hold {
            case .hold:
                return effect
            case .toggle:
                return current == effect ? .none : effect
            }
        }
    }

    /// The effect that should be active after the key comes back up, or `nil`
    /// to leave things exactly as they are.
    static func onRelease(_ id: BindingID, mode: ActivationMode?, duration: TimeInterval) -> Effect? {
        switch id {
        case .panic:
            return nil
        case .effect:
            // Only a hold clears, and no stored mode means the shipped default,
            // hold. Testing `mode == .hold` instead answers nil with nil, so a
            // nil-mode press latches its effect and this release never clears it.
            // A toggle's release carries no information.
            guard (mode ?? .hold) == .hold, isHold(duration) else { return nil }
            return Effect.none
        }
    }
}
