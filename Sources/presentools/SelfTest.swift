import AppKit
import Carbon

/// Headless proof that the effects paint the right pixels.
///
/// `screencapture` sampling failed twice: the cursor moves between runs and the
/// desktop is too dark to separate a 0.82 dim from an already-black background.
/// Here bounds and cursor are fixed and the surface starts solid white, so the
/// expected values are arithmetic rather than a judgement call.
@MainActor
enum SelfTest {
    /// Must exceed 2 * Look.spotlightRadius, otherwise the "dimmed" corners
    /// still sit inside the lit circle and the check passes for the wrong reason.
    private static let size = 1000
    private static let centre = size / 2
    private static let white: UInt8 = 255

    static func run() -> Bool {
        // The pixel checks assert on arithmetic that only holds for the shipped
        // look (`far ≈ 255 * (1 - 0.82)`). Rendering reads `Settings.shared`, so a
        // tuned install — `spotlightDim = 0.76` puts the surround at 61, one step
        // above the `< 60` bound — fails a suite that never tested anything
        // user-facing. Pin the two values the assertions depend on and put the
        // user's own values back afterwards; this must run before any other check
        // so nothing else observes the pinned state.
        let pinnedLook = PinnedLook()
        defer { pinnedLook.restore() }

        let spotlight = checkSpotlight()
        let edge = checkSpotlightEdge()
        let laser = checkLaser()
        let offSurface = checkEdgeClamp()
        let colors = checkPresetHex()
        let defaults = checkShippedBindings()
        let gestures = checkGestureDecisions()
        let hotkeys = checkHotKeyRegistration()
        let callback = checkHotKeyCallback()
        let persist = checkBindingPersistence()
        let conflicts = checkConflictRules()
        let glyphs = checkGlyphMap()
        let clicks = checkRecorderHitTesting()
        let version = checkVersion()
        let updates = checkUpdateLogic()
        let login = checkLaunchAtLoginMapping()
        let newSettings = checkNewSettingsDefaults()
        let sliders = checkSliderSpecs()

        let ok = spotlight && edge && laser && offSurface && colors && defaults && gestures && hotkeys && callback && persist && conflicts && glyphs && clicks && version && updates && login && newSettings && sliders
        print(ok ? "selftest: PASS" : "selftest: FAIL")
        return ok
    }

    /// A panel that opens but cannot be clicked is invisible to every other check:
    /// the layout is correct, the controls are enabled, and nothing throws. Only
    /// hit-testing proves the invisible recorder is not lying on top of them.
    /// AppKit tests subviews in reverse add order, so this is the one thing that
    /// regresses when the recorder is re-parented or its constraints change.
    private static func checkRecorderHitTesting() -> Bool {
        let panel = ShortcutRecorderWindow(
            bindings: HotKeyBinding.Defaults.bindings,
            onCommit: { _ in }
        )
        defer { panel.releaseWindow() }

        var ok = true
        // The window is ordered front by `hitTestReport`, otherwise every view
        // reports `nil` and the check would pass for the wrong reason.
        let probe = panel.hitTestReport()
        func name(_ v: NSView?) -> String { v.map { String(describing: type(of: $0)) } ?? "nil" }

        for line in panel.hitTestReport().lines {
            print("  \(line)")
        }

        let setOK = probe.setButton is NSButton
        print("  Set… button click target: \(setOK ? "ok" : "BLOCKED by \(name(probe.setButton))")")
        if !setOK { ok = false }

        let popupOK = probe.modePopup is NSPopUpButton
        print("  mode popup click target: \(popupOK ? "ok" : "BLOCKED by \(name(probe.modePopup))")")
        if !popupOK { ok = false }

        // The recorder must not be the answer at a point where a control lives,
        // and it must still exist in the hierarchy to take first responder.
        print("  recorder covers content: \(probe.recorderSwallows ? "SWALLOWS CLICKS" : "ok")")
        if probe.recorderSwallows { ok = false }

        return ok
    }

    /// Version comparison is where an update path most easily goes quietly wrong:
    /// `1.10.0` sorting below `1.9.0` as a string means a real update is never
    /// offered, and a tie being read as "newer" means the app offers to update to
    /// itself on every launch.
    private static func checkVersion() -> Bool {
        var ok = true
        func expect(_ label: String, _ got: Bool) {
            print("  version \(label): \(got ? "ok" : "BAD")")
            if !got { ok = false }
        }
        expect("1.10.0 > 1.9.0 numerically", Version.isNewer(current: "1.9.0", candidate: "1.10.0"))
        expect("1.9.0 not > 1.10.0", !Version.isNewer(current: "1.10.0", candidate: "1.9.0"))
        expect("1.2 == 1.2.0", !Version.isNewer(current: "1.2.0", candidate: "1.2"))
        expect("1.2.0 == 1.2", !Version.isNewer(current: "1.2", candidate: "1.2.0"))
        expect("v prefix stripped", Version.isNewer(current: "0.9.9", candidate: "v1.0.0"))
        expect("V prefix stripped", Version.isNewer(current: "0.9.9", candidate: "V1.0.0"))
        expect("suffix ignored for compare", Version.isNewer(current: "1.1.9", candidate: "1.2.0-beta1"))
        expect("suffix kept for display", Version.from("1.2.0-beta1")?.display == "1.2.0-beta1")
        expect("suffix parses to components", Version.from("1.2.0-beta1")?.components == [1, 2, 0])
        expect("tie is not newer", !Version.isNewer(current: "1.2.0", candidate: "1.2.0"))
        expect("older is not newer", !Version.isNewer(current: "1.2.1", candidate: "1.2.0"))
        expect("build metadata ignored", Version.isNewer(current: "1.2.0+1", candidate: "1.2.0+2") == false)
        expect("garbage parses to nil", Version.from("not-a-version") == nil)
        expect("empty parses to nil", Version.from("") == nil)
        expect("garbage current is not newer", !Version.isNewer(current: "???", candidate: "1.0.0"))
        expect("three components", Version.from("1.2.3")?.components == [1, 2, 3])
        expect("four components kept", Version.from("1.2.3.4")?.components == [1, 2, 3, 4])
        expect("whitespace trimmed", Version.from("  1.2.3  ")?.components == [1, 2, 3])
        expect("0.3.0 > 0.2.1", Version.isNewer(current: "0.2.1", candidate: "0.3.0"))
        return ok
    }

    /// The digest is the whole trust anchor of the update path: a release body
    /// that fails to parse correctly either blocks every update or, worse, skips
    /// verification. Both are silent, so they are proven here.
    private static func checkUpdateLogic() -> Bool {
        var ok = true
        func expect(_ label: String, _ got: Bool) {
            print("  update \(label): \(got ? "ok" : "BAD")")
            if !got { ok = false }
        }
        let hex = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        let upper = hex.uppercased()
        let other = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        expect("sha256: label", UpdateChecker.extractDigest(from: "sha256: \(hex)") == hex)
        expect("SHA256: label", UpdateChecker.extractDigest(from: "SHA256: \(hex)") == hex)
        expect("space separated", UpdateChecker.extractDigest(from: "SHA256 \(hex)") == hex)
        expect("shasum label", UpdateChecker.extractDigest(from: "shasum -a 256 \(hex)") == hex)
        expect("bare hex64", UpdateChecker.extractDigest(from: "\(hex)") == hex)
        expect("uppercase normalised", UpdateChecker.extractDigest(from: "SHA256: \(upper)") == hex)
        expect("first digest wins", UpdateChecker.extractDigest(from: "sha256: \(hex)\nshasum: \(other)") == hex)
        expect("digest is 64 chars", UpdateChecker.extractDigest(from: hex)?.count == 64)
        expect("63 hex is not a digest", UpdateChecker.extractDigest(from: String(hex.dropLast())) == nil)
        expect("65 hex is not a digest", UpdateChecker.extractDigest(from: hex + "a") == nil)
        expect("no digest in prose", UpdateChecker.extractDigest(from: "Release notes only, nothing here.") == nil)
        expect("empty body", UpdateChecker.extractDigest(from: "") == nil)

        // A release with no usable DMG is still "newer available"; the caller
        // has to notice the missing asset rather than the check failing.
        let noAsset = GitHubRelease(tag_name: "v9.9.9", name: nil, body: nil, html_url: nil, assets: [])
        let decoded = try? JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: [
            "tag_name": "v9.9.9", "name": "n", "body": "sha256: \(hex)",
            "html_url": "https://example.invalid", "assets": [["name": "Presentools-9.9.9.dmg", "browser_download_url": "https://example.invalid/a.dmg", "size": 10]],
        ]))
        expect("release decodes", decoded != nil)
        expect("dmg picked from assets", decoded?.assets?.first?.name == "Presentools-9.9.9.dmg")
        expect("missing assets decodes as empty", noAsset.assets?.isEmpty == true)

        expect("0.3.0 is newer than 0.2.1", UpdateChecker.isNewer(current: "0.2.1", tag: "v0.3.0"))
        expect("0.3.0 is not newer than 0.3.0", !UpdateChecker.isNewer(current: "0.3.0", tag: "v0.3.0"))
        expect("0.2.0 is not newer than 0.2.1", !UpdateChecker.isNewer(current: "0.2.1", tag: "v0.2.0"))
        expect("repo constant", UpdateChecker.repo == "ardith666/presentools")
        return ok
    }

    /// The login-item tick is derived from live `SMAppService.status`, never from a
    /// stored preference, so this proves the mapping the menu relies on for all
    /// four cases without registering anything.
    private static func checkLaunchAtLoginMapping() -> Bool {
        var ok = true
        func expect(_ label: String, _ got: Bool) {
            print("  login \(label): \(got ? "ok" : "BAD")")
            if !got { ok = false }
        }
        expect("enabled is on", LoginItemStatus.enabled.menuState == .on)
        expect("notRegistered is off", LoginItemStatus.notRegistered.menuState == .off)
        expect("requiresApproval is mixed", LoginItemStatus.requiresApproval.menuState == .mixed)
        expect("unknown is off", LoginItemStatus.unknown.menuState == .off)
        // Clicking a mixed tick has to be able to clear it, or the user is stuck
        // with an item that says "needs approval" and cannot be turned off here.
        expect("enabled click disables", !LoginItemStatus.enabled.shouldEnableOnClick)
        expect("notRegistered click enables", LoginItemStatus.notRegistered.shouldEnableOnClick)
        expect("requiresApproval click enables", LoginItemStatus.requiresApproval.shouldEnableOnClick)
        expect("unknown click enables", LoginItemStatus.unknown.shouldEnableOnClick)
        return ok
    }

    /// The first-run prompt is asked once per install. If `reset()` cleared the
    /// flag, a user who answered "Not Now" and later reset their look settings
    /// would be asked again — the "never re-asks" promise from the design.
    private static func checkNewSettingsDefaults() -> Bool {
        var ok = true
        func expect(_ label: String, _ got: Bool) {
            print("  setting \(label): \(got ? "ok" : "BAD")")
            if !got { ok = false }
        }
        let suite = "selftest.newsettings.\(ProcessInfo.processInfo.processIdentifier)"
        guard let d = UserDefaults(suiteName: suite) else {
            print("  setting suite: BAD (could not create)")
            return false
        }
        defer { d.removePersistentDomain(forName: suite) }

        // Shipped default: checks run at launch unless the user turns it off.
        let fresh = Settings(defaults: d)
        expect("autoUpdate defaults on", fresh.autoUpdate)
        expect("prompt flag starts false", !fresh.hasSeenLaunchAtLoginPrompt)

        fresh.hasSeenLaunchAtLoginPrompt = true
        fresh.reset()
        expect("reset keeps the prompt flag", fresh.hasSeenLaunchAtLoginPrompt)
        expect("reset restores autoUpdate", fresh.autoUpdate)

        let off = Settings(defaults: d)
        expect("persisted prompt flag reloaded", off.hasSeenLaunchAtLoginPrompt)

        d.set(false, forKey: "autoUpdate")
        expect("persisted autoUpdate=false reloads", !Settings(defaults: d).autoUpdate)

        // `defaults.bool(forKey:)` on an absent key is false, which would silently
        // disable updates; the default must win over absence.
        d.removeObject(forKey: "autoUpdate")
        expect("absent autoUpdate stays on", Settings(defaults: d).autoUpdate)
        return ok
    }

    /// The slider table is what a settings window is built from, so a bad entry
    /// is either a slider that cannot reach a legal value or a setting that
    /// quietly stopped being adjustable at all. Both are invisible until someone
    /// opens the window, so they are checked here instead.
    ///
    /// AppKit-free on purpose: these run in `--selftest` with no window server.
    private static func checkSliderSpecs() -> Bool {
        var ok = true
        func expect(_ label: String, _ got: Bool) {
            print("  slider \(label): \(got ? "ok" : "BAD")")
            if !got { ok = false }
        }

        // A range that excludes the shipped default snaps the slider to an end
        // the first time the window opens, which reads as the app ignoring the
        // setting rather than as a clamp.
        let shipped: [String: CGFloat] = [
            "Circle": Settings.Default.spotlightRadius,
            "Darkness": Settings.Default.spotlightDim,
            "Lens": Settings.Default.lensSide,
            "Magnify": Settings.Default.lensMagnification,
            "Dot": Settings.Default.laserRadius,
            "Line": Settings.Default.ringWidth,
        ]
        for section in SliderSection.all {
            for spec in section.sliders {
                guard let def = shipped[spec.label] else {
                    expect("\(section.title)/\(spec.label) has a shipped default", false)
                    continue
                }
                expect(
                    "\(section.title)/\(spec.label) range holds its default",
                    spec.range.contains(def)
                )
                expect("\(section.title)/\(spec.label) has positive step", spec.step > 0)
            }
        }

        // The one that matters most: every numeric setting must appear exactly
        // once, bound to the setting it names. A mistyped keypath compiles fine
        // and silently drives its neighbour's setting.
        let labels = SliderSection.all.flatMap { $0.sliders.map(\.label) }
        expect("6 sliders declared", labels.count == 6)
        for want in ["Circle", "Darkness", "Lens", "Magnify", "Dot", "Line"] {
            expect("has \(want)", labels.filter { $0 == want }.count == 1)
        }
        expect("no duplicate labels", Set(labels).count == labels.count)

        // Section order is the sidebar the user reads top to bottom, specified as
        // Spotlight / Zoom Lens / Laser Pointer / Edge. Expected titles are literal
        // so reversing the table fails instead of rendering the sidebar backwards.
        let order: [String] = ["Spotlight", "Zoom Lens", "Laser Pointer", "Edge"]
        expect("4 sections declared", SliderSection.all.count == order.count)
        expect("sidebar order", SliderSection.all.map(\.title) == order)
        let keypaths: [String: ReferenceWritableKeyPath<Settings, CGFloat>] = [
            "Circle": \.spotlightRadius,
            "Darkness": \.spotlightDim,
            "Lens": \.lensSide,
            "Magnify": \.lensMagnification,
            "Dot": \.laserRadius,
            "Line": \.ringWidth,
        ]
        for section in SliderSection.all {
            for spec in section.sliders {
                guard let want = keypaths[spec.label] else {
                    expect("\(section.title)/\(spec.label) has an expected keypath", false)
                    continue
                }
                expect("\(section.title)/\(spec.label) drives its own setting", spec.keyPath == want)
            }
        }

        // A readout that rounds below its own step renders every reachable value
        // in the gap as the same string, so the slider looks stuck while it moves.
        for section in SliderSection.all {
            for spec in section.sliders {
                let low = spec.range.lowerBound
                expect(
                    "\(section.title)/\(spec.label) readout separates one step",
                    spec.format(low) != spec.format(low + spec.step)
                )
            }
        }

        // Colour sections carry a keypath or the swatches cannot write anywhere,
        // and it has to be the one for that section's own setting: a swapped
        // keypath compiles fine and silently recolours the neighbouring effect.
        let colorKeypaths: [String: ReferenceWritableKeyPath<Settings, NSColor>] = [
            "Laser Pointer": \.laserColor,
            "Edge": \.ringColor,
        ]
        for section in SliderSection.all where !section.colorPresets.isEmpty {
            expect("\(section.title) has a colour keypath", section.colorKeyPath != nil)
            guard let want = colorKeypaths[section.title] else {
                expect("\(section.title) has an expected colour keypath", false)
                continue
            }
            expect(
                "\(section.title) drives its own colour",
                section.colorKeyPath == want
            )
        }

        // Clamping is the whole guard against a value written outside the range
        // by an older build.
        func section(_ title: String) -> SliderSection? {
            SliderSection.all.first { $0.title == title }
        }
        if let circle = SliderSection.all.first(where: { $0.title == "Spotlight" })?
            .sliders.first(where: { $0.label == "Circle" }) {
            expect("clamp below -> low", circle.clamped(-999) == circle.range.lowerBound)
            expect("clamp above -> high", circle.clamped(9999) == circle.range.upperBound)
            expect("clamp inside -> unchanged", circle.clamped(200) == 200)
        } else {
            expect("Spotlight/Circle slider exists", false)
        }

        // Each effect has to be reachable from its own section. A union of every
        // section's preview cannot tell two sections apart: retarget the lens at
        // the spotlight and the set is unchanged.
        let previews: [(String, Effect)] = [
            ("Spotlight", .spotlight), ("Zoom Lens", .zoom), ("Laser Pointer", .laser),
        ]
        for (title, want) in previews {
            guard let found = section(title) else {
                expect("\(title) section exists", false)
                continue
            }
            expect(
                "\(title) previews onto \(want.rawValue)",
                Effect.allCases.allSatisfy { found.previewEffect(current: $0) == want }
            )
        }
        if let edge = section("Edge") {
            // Dragging Line while the lens is up must not replace the lens.
            expect("Edge keeps the lens", edge.previewEffect(current: .zoom) == .zoom)
            expect("Edge keeps the spotlight", edge.previewEffect(current: .spotlight) == .spotlight)
            // Laser has no ring, so Edge borrows the spotlight.
            expect("Edge falls back past the laser", edge.previewEffect(current: .laser) == .spotlight)
        } else {
            expect("Edge section exists", false)
        }

        expect("percent formats", SliderSection.percent(0.82) == "82%")
        expect("magnify formats", SliderSection.magnify(2) == "2.0x")
        expect("sub-point formats", SliderSection.points(0.5) == "0.5 pt")
        return ok
    }

    /// The shipped bindings are the contract with anyone who learned them from the
    /// menu: Off ⌥0, Spotlight ⌥1, Laser ⌥2, Zoom ⌥3, panic ⌥Esc. Digests are
    /// compared rather than literal key codes so a typo in a constant shows up here
    /// instead of silently rebinding a user.
    private static func checkShippedBindings() -> Bool {
        let want: [BindingID: String] = [
            .effect(.none):      "1D:opt",
            .effect(.spotlight): "12:opt",
            .effect(.laser):     "13:opt",
            .effect(.zoom):      "14:opt",
            .panic:              "35:opt",
        ]
        var ok = true
        // Walk `BindingID.all`, not `want`: an effect case that ships without a
        // binding, or a binding added without an expectation, has to fail loudly
        // instead of depending on dictionary iteration order to be noticed.
        for id in BindingID.all {
            guard let expected = want[id] else {
                print("  binding \(id.title): NO EXPECTATION (add it to `want`)")
                ok = false
                continue
            }
            guard let binding = HotKeyBinding.Defaults.bindings[id] else {
                print("  binding \(id.title): MISSING (want \(expected))")
                ok = false
                continue
            }
            // Padded so a future low code renders "0F" against the "0F" literal,
            // not "F" against "0F".
            let got = "\(String(format: "%02X", binding.key.keyCode)):\(HotKeyBinding.digest(binding.key.modifiers))"
            let wantMode: ActivationMode? = id == .panic ? nil : .toggle
            let modeOk = binding.mode == wantMode
            print("  binding \(id.title): \(got) \(got == expected && modeOk ? "ok" : "BAD") (want \(expected), mode \(wantMode?.rawValue ?? "nil"))")
            if got != expected || !modeOk { ok = false }
        }
        return ok
    }

    /// Every tap/hold/toggle outcome, driven without Carbon so the whole matrix is
    /// provable in one run. `onRelease` returning `nil` means "change nothing",
    /// which is a different answer from returning `Effect.none`, which means
    /// "turn everything off".
    ///
    /// Expectations that mean "turn everything off" are written `Effect.none`,
    /// never a bare `.none`: the `expect` parameter is `Effect?`, and Swift reads
    /// a bare `.none` there as `Optional.none`. Such an expectation silently
    /// agrees with a bare `.none` in the code under test, so the check passes
    /// while a spotlight is still on screen after a long hold — the one failure
    /// this whole feature exists to prevent.
    private static func checkGestureDecisions() -> Bool {
        var ok = true

        func expect(_ label: String, _ got: Effect?, _ want: Effect?) {
            let good = got == want
            print("  decision \(label): \(got.map(\.title) ?? "no change")\(good ? " ok" : " BAD")")
            if !good { ok = false }
        }

        expect("tap threshold 0.24 is a tap", HotKeyDecision.isHold(0.24) ? .spotlight : nil, nil)
        expect("tap threshold 0.25 is a hold", HotKeyDecision.isHold(0.25) ? .spotlight : nil, .spotlight)

        // Panic clears whatever is active, whatever the mode.
        expect("panic press", HotKeyDecision.onPress(.panic, mode: nil, current: .laser), Effect.none)

        // Hold: press applies, quick release keeps, long release clears.
        expect("hold press", HotKeyDecision.onPress(.effect(.laser), mode: .hold, current: .none), .laser)
        expect("hold quick release", HotKeyDecision.onRelease(.effect(.laser), mode: .hold, duration: 0.1), nil)
        expect("hold long release", HotKeyDecision.onRelease(.effect(.laser), mode: .hold, duration: 2.0), Effect.none)

        // No stored mode is the shipped default, hold, so press and release have
        // to agree on that. A release that read nil as "not a hold" would answer
        // "no change" and leave the press's spotlight on screen forever.
        expect("nil mode long release", HotKeyDecision.onRelease(.effect(.spotlight), mode: nil, duration: 2.0), Effect.none)
        // Panic cleared on its own press, so its release must report "no change"
        // rather than `Effect.none`: clearing again would wipe whatever the user
        // turned on between the two.
        expect("panic release ignored", HotKeyDecision.onRelease(.panic, mode: nil, duration: 2.0), nil)

        // Toggle: press flips, release never changes anything.
        expect("toggle on", HotKeyDecision.onPress(.effect(.zoom), mode: .toggle, current: .none), .zoom)
        expect("toggle off", HotKeyDecision.onPress(.effect(.zoom), mode: .toggle, current: .zoom), Effect.none)
        expect("toggle release ignored", HotKeyDecision.onRelease(.effect(.zoom), mode: .toggle, duration: 2.0), nil)

        // Auto-repeat must be a no-op, or a held key flickers.
        expect("auto repeat", HotKeyDecision.onAutoRepeat(.effect(.laser), nil), nil)

        return ok
    }

    /// Carbon registration against the real window server. A combination owned by
    /// another app comes back as a failure rather than a crash, which is the
    /// behaviour the recorder window reports back to the user.
    private static func checkHotKeyRegistration() -> Bool {
        let center = HotKeyCenter(onPress: { _ in }, onRelease: { _, _ in })
        let result = center.start(bindings: HotKeyBinding.Defaults.bindings)
        var ok = result.count == HotKeyBinding.Defaults.bindings.count
        for id in BindingID.all {
            let registered = result[id] ?? false
            print("  register \(id.title): \(registered ? "ok" : "FAILED")")
            if !registered { ok = false }
        }
        center.stop()
        return ok
    }

    /// The dispatch path `HotKeyCenter` runs when Carbon delivers an event,
    /// which `--selftest` otherwise never reaches: `checkHotKeyRegistration`
    /// proves the combinations register and nothing else. Timestamping the press,
    /// dropping an auto-repeat and pairing a release with its press all live
    /// here, and every one of the three failing leaves the spotlight on screen
    /// with no key down.
    ///
    /// Timestamps are literals so no case waits on the clock, and the Carbon ids
    /// come from `testCarbonID` rather than from a live registration, which
    /// another app may already own.
    private static func checkHotKeyCallback() -> Bool {
        var ok = true
        let id = BindingID.effect(.spotlight)

        func expect(_ label: String, _ good: Bool, _ detail: String) {
            print("  callback \(label): \(good ? "ok" : "BAD") (\(detail))")
            if !good { ok = false }
        }
        /// "none" rather than a fabricated number, so a case that must not report
        /// a duration cannot accidentally agree with zero.
        func shown(_ release: (BindingID, TimeInterval)?) -> String {
            release.map { String(format: "%.2f", $0.1) } ?? "none"
        }

        // A repeat mid-hold must not restart the clock. If it did, this release
        // would report 0.80 instead of 1.00 — still past the 0.25 hold
        // threshold, so a `pressedAt`-only assertion would pass while the
        // measurement was provably restarted. The duration is the assertion.
        var presses = 0
        var held: (BindingID, TimeInterval)?
        let center = HotKeyCenter(onPress: { _ in presses += 1 },
                                  onRelease: { held = ($0, $1) })
        let carbon = center.testCarbonID(for: id)
        center.handlePress(carbon, now: 0)
        center.handlePress(carbon, now: 0.20)  // auto-repeat, still down
        center.handleRelease(carbon, now: 1.0)
        expect("repeat keeps the hold", presses == 1 && held?.0 == id
            && held?.1 == 1.0 && HotKeyDecision.isHold(held?.1 ?? 0),
            "presses=\(presses) duration=\(shown(held)) isHold=\(HotKeyDecision.isHold(held?.1 ?? 0)) (want 1, 1.00, true)")

        // A release with no press behind it — the app launched while the key was
        // already down, or the press was swallowed — must change nothing rather
        // than report a duration, which would switch off an effect the user
        // never turned on.
        var orphans = 0
        var orphan: (BindingID, TimeInterval)?
        let unpaired = HotKeyCenter(onPress: { _ in orphans += 1 },
                                    onRelease: { orphan = ($0, $1) })
        unpaired.handleRelease(unpaired.testCarbonID(for: id), now: 5.0)
        expect("release without a press", orphans == 0 && orphan == nil,
            "presses=\(orphans) duration=\(shown(orphan)) (want 0, none)")

        // The duration arithmetic itself. A negative delta is the wall-clock
        // step backwards `Self.uptime` exists to keep out of the app, a
        // sub-threshold delta is a tap, and the exact 0.25 boundary is included
        // because it is the single value that separates the two.
        for (pressAt, releaseAt, wantHold) in [(1.0, 0.9, false), (1.0, 1.24, false), (0.75, 1.0, true)] {
            var timed: (BindingID, TimeInterval)?
            let clock = HotKeyCenter(onPress: { _ in }, onRelease: { timed = ($0, $1) })
            let timedID = clock.testCarbonID(for: id)
            clock.handlePress(timedID, now: pressAt)
            clock.handleRelease(timedID, now: releaseAt)
            expect("delta \(shown((id, releaseAt - pressAt)))", timed?.0 == id
                && HotKeyDecision.isHold(timed?.1 ?? 0) == wantHold,
                "duration=\(shown(timed)) isHold=\(HotKeyDecision.isHold(timed?.1 ?? 0)) (want \(wantHold))")
        }

        return ok
    }

    /// Every menu preset must survive `hexString`. `.white` is a tagged-pointer
    /// catalog colour in Generic Gray Gamma 2.2, and reading `redComponent`
    /// off one raises `NSInvalidArgumentException` instead of returning a
    /// value. Thrown from `rebuildMenu`, it aborted
    /// `applicationDidFinishLaunching`, so `statusItem.menu` was never
    /// assigned and clicking the menu bar item showed nothing.
    private static func checkPresetHex() -> Bool {
        var ok = true
        for (name, color) in Settings.laserPresets + Settings.ringPresets {
            // Reaching this line at all is half the test: the old hexString
            // raised here instead of returning.
            let hex = color.hexString
            let wellFormed = hex.count == 7 && hex.first == "#"
            let stable = NSColor(hex: hex)?.hexString == hex
            let white = color != .white || hex == "#FFFFFF"
            if !(wellFormed && stable && white) { ok = false }
            print("  presetHex \(name): \(hex) \(wellFormed && stable && white ? "ok" : "BAD") (want #RRGGBB, round-trips)")
        }
        return ok
    }

    /// The user asked for a hard circle edge, not a soft ramp. Sample just
    /// inside and just outside the ring: a gradient can never jump this far
    /// across 12pt, so this is the check that actually proves the shape.
    private static func checkSpotlightEdge() -> Bool {
        let r = Int(Look.spotlightRadius)
        let (p, w, _) = render(.spotlight, cursor: CGPoint(x: centre, y: centre))
        let inside = lum(p, centre + r - 6, centre, w)
        let outside = lum(p, centre + r + 6, centre, w)
        print("  spotlightEdge: inside=\(Int(inside)) outside=\(Int(outside)) (want >240, <60, jump)")
        return inside > 240 && outside < 60
    }

    /// Bindings must survive a relaunch, and a damaged record must degrade to the
    /// shipped default instead of leaving an effect with no way to switch it on.
    ///
    /// Runs against a throwaway `UserDefaults` suite, never `.standard`: writing
    /// the real domain would leave the user's own hotkeys and look settings
    /// whatever this check happened to leave behind, even on a passing run.
    private static func checkBindingPersistence() -> Bool {
        func expect(_ label: String, _ good: Bool, _ detail: String) {
            print("  persist \(label): \(good ? "ok" : "BAD") (\(detail))")
        }

        // Non-nil but almost certainly unused, so a run cannot disturb a real suite.
        guard let store = UserDefaults(suiteName: "presentools.selftest.hotkeys") else {
            print("  persist: NO SUITE (UserDefaults(suiteName:) returned nil)")
            return false
        }
        store.removePersistentDomain(forName: "presentools.selftest.hotkeys")
        defer { store.removePersistentDomain(forName: "presentools.selftest.hotkeys") }

        var ok = true
        let settings = Settings(defaults: store)

        // Written as literal keys, not built from the same helpers the setter
        // uses, so this pins the on-disk format instead of agreeing with itself.
        let laserKeyCode = "hotkey.effect.laser.keyCode"
        let laserModifiers = "hotkey.effect.laser.modifiers"
        let laserMode = "hotkey.effect.laser.mode"
        let zoomModifiers = "hotkey.effect.zoom.modifiers"

        var custom = HotKeyBinding.Defaults.bindings
        custom[.effect(.laser)] = EffectBinding(
            key: HotKeyBinding(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | optionKey)),
            mode: .toggle
        )
        settings.hotKeyBindings = custom

        let reread = settings.hotKeyBindings
        let laser = reread[.effect(.laser)]
        let roundTrip = laser?.key.keyCode == UInt32(kVK_ANSI_9)
            && laser?.key.modifiers == UInt32(cmdKey | optionKey)
            && laser?.mode == .toggle
        // The literal keys themselves, so a rename of the storage helpers shows
        // up here instead of the getter and the setter agreeing on a new format.
        let onDisk = store.object(forKey: laserKeyCode) as? Int == Int(kVK_ANSI_9)
            && store.object(forKey: laserModifiers) as? Int == Int(cmdKey | optionKey)
            && store.string(forKey: laserMode) == ActivationMode.toggle.rawValue
        expect("custom binding round-trips", roundTrip && onDisk,
            "keyCode=\(laser.map { String(format: "%02X", $0.key.keyCode) } ?? "none") mode=\(laser?.mode?.rawValue ?? "nil") (want 19, toggle), on disk=\(onDisk)")

        // Every binding except laser has to come back exactly as shipped, panic's
        // `nil` mode included. `nil` is not missing data: it is what says "this
        // binding has no mode", and reading it as anything else changes what a
        // press and a release do.
        let untouched = BindingID.all
            .filter { $0 != .effect(.laser) }
            .allSatisfy { reread[$0] == HotKeyBinding.Defaults.bindings[$0] }
        let panicNil = reread[.panic]?.mode == nil
        expect("untouched bindings unchanged, panic mode nil", untouched && panicNil,
            "panic mode=\(reread[.panic]?.mode?.rawValue ?? "nil") (want nil)")

        // An unrecognised mode string falls back to that binding's shipped default,
        // not to a mode invented at the load site. It must not be rejected
        // outright either: a mode-less binding that activates but never clears
        // leaves the spotlight stuck.
        store.set("nonsense", forKey: laserMode)
        let fallback = settings.hotKeyBindings[.effect(.laser)]?.mode
        let wantFallback = HotKeyBinding.Defaults.bindings[.effect(.laser)]?.mode
        expect("bad mode string falls back to shipped default", fallback == wantFallback,
            "mode=\(fallback?.rawValue ?? "nil") (want \(wantFallback?.rawValue ?? "nil"))")

        // No mode key at all is the same answer as an unreadable one: the shipped
        // default. The custom key code still stands, so the record is half-used
        // rather than thrown away.
        store.removeObject(forKey: laserMode)
        let noMode = settings.hotKeyBindings[.effect(.laser)]
        let noModeFallsBack = noMode?.mode == wantFallback
            && noMode?.key.keyCode == UInt32(kVK_ANSI_9)
        expect("absent mode means shipped default, key survives", noModeFallsBack,
            "keyCode=\(noMode.map { String(format: "%02X", $0.key.keyCode) } ?? "none") mode=\(noMode?.mode?.rawValue ?? "nil") (want 19, \(wantFallback?.rawValue ?? "nil"))")

        // One unusable record must not reset the rest of the table. A wholesale
        // fallback would quietly hand back every shipped default here, including
        // laser, which the user deliberately set to toggle.
        settings.hotKeyBindings = custom
        store.set("not-a-number", forKey: zoomModifiers)
        let mixed = settings.hotKeyBindings
        let perBinding = mixed[.effect(.laser)]?.mode == .toggle
            && mixed[.effect(.zoom)]?.key == HotKeyBinding.Defaults.bindings[.effect(.zoom)]?.key
        expect("malformed binding falls back alone", perBinding,
            "laser mode=\(mixed[.effect(.laser)]?.mode?.rawValue ?? "nil") (want toggle), zoom=\(HotKeyBinding.digest(mixed[.effect(.zoom)]?.key.modifiers ?? 0)) (want opt)")

        // A record can cast to `Int` and still be lethal: `RegisterEventHotKey`
        // validates nothing, so zero modifiers on an effect would register a bare
        // global keystroke that swallows the key app-wide while the user types.
        // The check has to bite on load, where a disk record first arrives.
        store.set(Int(UInt32(kVK_ANSI_9)), forKey: "hotkey.effect.zoom.keyCode")
        store.set(0, forKey: "hotkey.effect.zoom.modifiers")
        let bareZoom = settings.hotKeyBindings[.effect(.zoom)]
        expect("bare effect binding rejected on load", bareZoom == HotKeyBinding.Defaults.bindings[.effect(.zoom)],
            "zoom=\(HotKeyBinding.digest(bareZoom?.key.modifiers ?? 0)) (want opt, not bare)")

        // Panic is the deliberate exception: bare modifier is a legal choice
        // there, so this must be accepted rather than reset to the shipped ⌥Esc.
        store.set(Int(UInt32(kVK_Escape)), forKey: "hotkey.panic.keyCode")
        store.set(0, forKey: "hotkey.panic.modifiers")
        let barePanic = settings.hotKeyBindings[.panic]
        expect("bare panic binding accepted", barePanic == EffectBinding(
            key: HotKeyBinding(keyCode: UInt32(kVK_Escape), modifiers: 0), mode: nil),
            "panic=\(HotKeyBinding.digest(barePanic?.key.modifiers ?? 0)) (want none, mode=\(barePanic?.mode?.rawValue ?? "nil") want nil)")

        // Modifiers here are valid, so the only thing wrong is the key code: the
        // plausibility bound has to reject it on its own.
        store.set(9999, forKey: "hotkey.effect.laser.keyCode")
        store.set(Int(UInt32(cmdKey | optionKey)), forKey: "hotkey.effect.laser.modifiers")
        let wildLaser = settings.hotKeyBindings[.effect(.laser)]
        expect("implausible key code rejected", wildLaser == HotKeyBinding.Defaults.bindings[.effect(.laser)],
            "keyCode=\(wildLaser.map { String(format: "%02X", $0.key.keyCode) } ?? "none") (want 13, shipped)")

        // The setter owns exactly its own keys. `removePersistentDomain` here
        // would take the look settings down with them, since they share the same
        // `UserDefaults` domain.
        store.set("#00FF00", forKey: "laserColor")
        settings.hotKeyBindings = HotKeyBinding.Defaults.bindings
        let lookIntact = store.string(forKey: "laserColor") == "#00FF00"
        let backToShipped = settings.hotKeyBindings == HotKeyBinding.Defaults.bindings
        expect("reset keeps unrelated look settings", lookIntact && backToShipped,
            "laserColor=\(store.string(forKey: "laserColor") ?? "nil") (want #00FF00), table back to shipped=\(backToShipped)")

        // A binding left out of the table is removed from disk, not written
        // through, so a stale record cannot outlive the binding that made it.
        var withoutZoom = HotKeyBinding.Defaults.bindings
        withoutZoom.removeValue(forKey: .effect(.zoom))
        settings.hotKeyBindings = withoutZoom
        let zoomKeyGone = store.object(forKey: "hotkey.effect.zoom.keyCode") == nil
            && store.object(forKey: "hotkey.effect.zoom.modifiers") == nil
        let zoomReadsDefault = settings.hotKeyBindings[.effect(.zoom)] == HotKeyBinding.Defaults.bindings[.effect(.zoom)]
        expect("dropped binding is erased, not ignored", zoomKeyGone && zoomReadsDefault,
            "zoom keys gone=\(zoomKeyGone), zoom reads shipped=\(zoomReadsDefault)")

        // `reset()` itself, not a hand-written copy of its body: the setter block
        // above assigns `HotKeyBinding.Defaults.bindings` directly, which meant
        // deleting the hotkey line inside `reset()` changed nothing the suite
        // could see. The custom table has to be on disk first, otherwise the
        // getter's own shipped fallback hides the missing reset. A fresh
        // instance over the same store also pins that `reset` reaches the look
        // settings, which this path never exercised before.
        store.set("#00FF00", forKey: "laserColor")
        var preReset = HotKeyBinding.Defaults.bindings
        preReset[.effect(.zoom)] = EffectBinding(
            key: HotKeyBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | optionKey)),
            mode: .toggle
        )
        settings.hotKeyBindings = preReset
        let reset = Settings(defaults: store)
        reset.reset()
        let resetTable = reset.hotKeyBindings == HotKeyBinding.Defaults.bindings
        let resetLook = reset.laserColor == Settings.Default.laserColor
            && store.string(forKey: "laserColor") == Settings.Default.laserColor.hexString
        expect("reset() restores every value", resetTable && resetLook,
            "zoom=\(HotKeyBinding.digest(reset.hotKeyBindings[.effect(.zoom)]?.key.modifiers ?? 0)) keyCode=\(reset.hotKeyBindings[.effect(.zoom)].map { String(format: "%02X", $0.key.keyCode) } ?? "none") mode=\(reset.hotKeyBindings[.effect(.zoom)]?.mode?.rawValue ?? "nil") (want 14 opt toggle), laserColor=\(store.string(forKey: "laserColor") ?? "nil") (want \(Settings.Default.laserColor.hexString))")

        ok = roundTrip && onDisk && untouched && panicNil && fallback == wantFallback && noModeFallsBack && perBinding
            && bareZoom == HotKeyBinding.Defaults.bindings[.effect(.zoom)]
            && barePanic?.key.modifiers == 0
            && wildLaser == HotKeyBinding.Defaults.bindings[.effect(.laser)]
            && lookIntact && backToShipped && zoomKeyGone && zoomReadsDefault
            && resetTable && resetLook
        return ok
    }

    /// A rejected binding keeps the previous one, so `reason` has to say why in
    /// words the user can act on. Every rule in the spec is exercised here.
    private static func checkConflictRules() -> Bool {
        let cmd = UInt32(cmdKey)
        let table = HotKeyBinding.Defaults.bindings
        var ok = true

        /// Must be refused, and the message has to be a sentence rather than a
        /// bare "no", since the menu shows it verbatim.
        func check(_ label: String, _ candidate: HotKeyBinding, id: BindingID = .effect(.laser)) {
            let reason = HotKeyConflict.reason(for: candidate, id: id, in: table)
            let good = reason != nil
            print("  conflict \(label): \(reason ?? "ACCEPTED")\(good ? " ok" : " BAD")")
            if !good { ok = false }
        }

        /// Must be accepted. `check` proves a rule bites; this proves it did not
        /// bite too far, which is the failure a user notices as a hot key that
        /// will not save.
        func allow(_ label: String, _ candidate: HotKeyBinding, id: BindingID = .effect(.laser),
                   in table: [BindingID: EffectBinding] = table) {
            let reason = HotKeyConflict.reason(for: candidate, id: id, in: table)
            let good = reason == nil
            print("  conflict \(label): \(reason.map { "REFUSED \($0)" } ?? "ACCEPTED")\(good ? " ok" : " BAD")")
            if !good { ok = false }
        }

        check("duplicate of spotlight", HotKeyBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey)))
        check("⌘Space", HotKeyBinding(keyCode: UInt32(kVK_Space), modifiers: cmd))
        check("⌘Tab", HotKeyBinding(keyCode: UInt32(kVK_Tab), modifiers: cmd))
        check("bare letter", HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: 0))
        check("shift only", HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey)))
        check("F5 with no modifier", HotKeyBinding(keyCode: UInt32(kVK_F5), modifiers: 0))

        // Full combinations, not key codes: spotlight holds ⌥1, so ⌘1 is a
        // different chord and has to stay available.
        allow("⌘1 beside ⌥1", HotKeyBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: cmd))

        // The panic key may take bare Esc; an effect binding may not.
        allow("bare Esc on panic", HotKeyBinding(keyCode: UInt32(kVK_Escape), modifiers: 0), id: .panic)

        // Self-comparison: a binding held in its own entry is not a conflict, or
        // every edit would be refused and the table could never be changed.
        // `reason` skips `id` itself, so the caller must not have to remove it.
        allow("its own current value", HotKeyBinding.Defaults.bindings[.effect(.laser)]!.key)

        // The shipped table must survive its own rules.
        var defaultsOK = true
        for (id, binding) in table {
            if let reason = HotKeyConflict.reason(for: binding.key, id: id, in: table) {
                print("  conflict shipped \(id.title) is itself invalid: \(reason) BAD")
                defaultsOK = false
            }
        }
        if defaultsOK { print("  conflict shipped defaults all pass: ok") } else { ok = false }

        return ok
    }

    /// Every shipped binding must render to the label the menu already teaches.
    /// This is the only proof that the key-name table is complete: Carbon's codes
    /// are not contiguous, so a missing entry falls through to `key 18` and the
    /// user sees a raw number in the recorder.
    private static func checkGlyphMap() -> Bool {
        var ok = true
        for (id, want) in [
            (BindingID.effect(.none), "⌥0"),
            (BindingID.effect(.spotlight), "⌥1"),
            (BindingID.effect(.laser), "⌥2"),
            (BindingID.effect(.zoom), "⌥3"),
            (BindingID.panic, "⌥Esc"),
        ] {
            guard let key = HotKeyBinding.Defaults.bindings[id]?.key else {
                print("  glyph \(id.title): MISSING BAD")
                ok = false
                continue
            }
            let got = HotKeyConflict.describe(key)
            let good = got == want
            print("  glyph \(id.title): \(got)\(good ? " ok" : " BAD (want \(want))")")
            if !good { ok = false }
        }
        return ok
    }

    /// Temporarily forces the shipped look so the pixel checks are deterministic,
    /// then puts the user's tuned values back. Both values are written through the
    /// real setters, which persist; the restore writes the same values the user
    /// already had, so the on-disk state is unchanged.
    @MainActor
    private struct PinnedLook {
        private let dim: CGFloat
        private let radius: CGFloat

        init() {
            dim = Settings.shared.spotlightDim
            radius = Settings.shared.spotlightRadius
            Settings.shared.spotlightDim = Settings.Default.spotlightDim
            Settings.shared.spotlightRadius = Settings.Default.spotlightRadius
        }

        func restore() {
            Settings.shared.spotlightDim = dim
            Settings.shared.spotlightRadius = radius
        }
    }

    /// Renders one effect over a solid white surface and hands back the pixels.
    private static func render(_ effect: Effect, cursor: CGPoint) -> (pixels: [UInt8], w: Int, h: Int) {
        let w = size, h = size
        var pixels = [UInt8](repeating: white, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("bitmap context") }

        let view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        // Start opaque white so "not drawn" and "drawn dark" are distinguishable.
        NSColor.white.setFill()
        view.bounds.fill()
        effect.draw(in: view, cursor: cursor)
        NSGraphicsContext.restoreGraphicsState()
        return (pixels, w, h)
    }

    /// p is w*h*4 bytes; the row stride is w*4, not p.count/4.
    private static func lum(_ p: [UInt8], _ x: Int, _ y: Int, _ w: Int) -> Double {
        let i = (y * w + x) * 4
        return 0.299 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.114 * Double(p[i + 2])
    }

    private static func red(_ p: [UInt8], _ x: Int, _ y: Int, _ w: Int) -> Double {
        Double(p[(y * w + x) * 4])
    }

    /// Under the pointer the slide must stay readable; far from it, dimmed.
    private static func checkSpotlight() -> Bool {
        let (p, w, h) = render(.spotlight, cursor: CGPoint(x: centre, y: centre))

        let atCursor = lum(p, centre, centre, w)
        let far = (lum(p, 5, 5, w) + lum(p, w - 5, 5, w) + lum(p, 5, h - 5, w) + lum(p, w - 5, h - 5, w)) / 4

        // far ~= 255 * (1 - 0.82) ~= 46; cursor must stay near white.
        print("  spotlight: cursor=\(Int(atCursor)) far=\(Int(far)) (want >240, <60)")
        return far < 60 && atCursor > 240
    }

    /// A red dot at the cursor, and nothing anywhere else.
    private static func checkLaser() -> Bool {
        let (p, w, h) = render(.laser, cursor: CGPoint(x: centre, y: centre))

        let atCursor = red(p, centre, centre, w)
        let off = (red(p, 20, 20, w) + red(p, w - 20, h - 20, w)) / 2
        print("  laser: dot=\(Int(atCursor)) rest=\(Int(off)) (want >200, >240)")
        return atCursor > 200 && off > 240
    }

    /// A cursor outside the surface must not crash or paint the whole surface.
    private static func checkEdgeClamp() -> Bool {
        let (p, w, _) = render(.spotlight, cursor: CGPoint(x: -500, y: -500))
        let centreLum = lum(p, centre, centre, w)
        print("  edge: offSurfaceCentre=\(Int(centreLum)) (want <60, no crash)")
        return centreLum < 60
    }
}
