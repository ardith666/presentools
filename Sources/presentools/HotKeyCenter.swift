import AppKit
import Carbon

/// Global hotkeys. AppKit has no API for these — `RegisterEventHotKey` from
/// Carbon is the only supported path, which is why the app links Carbon at all.
///
/// The same registration also emits `kEventHotKeyReleased` with the same
/// `EventHotKeyID`, so press and release arrive here without a `CGEventTap` and
/// without Accessibility permission.
@MainActor
final class HotKeyCenter {
    private static let signature: OSType = 0x5048_544B  // 'PTHK'

    /// Seconds since boot, not `Date()`. A wall clock can step backwards when the
    /// user changes it or an NTP correction lands, and a negative duration would
    /// read as a tap and skip the clear that ends a hold — the spotlight would
    /// then stay on screen with no key still down.
    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var refs: [BindingID: EventHotKeyRef] = [:]
    /// Carbon identifies a hotkey by a plain UInt32, so a reverse map is needed
    /// to get back to the binding the user actually configured.
    private var ids: [UInt32: BindingID] = [:]
    private var handler: EventHandlerRef?
    /// When each currently-held binding went down. Presence here is what
    /// distinguishes a genuine release from an auto-repeat.
    private var pressedAt: [BindingID: TimeInterval] = [:]

    private let onPress: (BindingID) -> Void
    private let onRelease: (BindingID, TimeInterval) -> Void

    var registeredCount: Int { refs.count }

    init(onPress: @escaping (BindingID) -> Void,
         onRelease: @escaping (BindingID, TimeInterval) -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    // No deinit: the process lives for the whole app run, so unregistering on
    // deallocation is dead code. stop() stays public for explicit teardown.

    // MARK: Lifecycle

    /// Registers every binding and reports which ones Carbon accepted. A
    /// combination another app already owns fails here; that is not fatal, the
    /// other bindings still work and the caller can show the user which one
    /// went missing.
    ///
    /// Precondition: call `stop()` first when passing different bindings. A
    /// second call while the handler is installed returns a cache of the live
    /// registrations and ignores its argument, so re-registering after a
    /// settings change without stopping would silently keep the old keys.
    func start(bindings: [BindingID: EffectBinding]) -> [BindingID: Bool] {
        guard handler == nil else {
            var cached: [BindingID: Bool] = [:]
            for id in BindingID.all { cached[id] = refs[id] != nil }
            return cached
        }

        // Two specs, not two handlers: press and release share one callback.
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let status = specs.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                    var id = EventHotKeyID()
                    let got = GetEventParameter(
                        event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &id
                    )
                    guard got == noErr, id.signature == HotKeyCenter.signature else { return got }
                    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                    let kind = GetEventKind(event)
                    return MainActor.assumeIsolated {
                        if kind == UInt32(kEventHotKeyPressed) {
                            center.handlePress(id.id)
                        } else if kind == UInt32(kEventHotKeyReleased) {
                            center.handleRelease(id.id)
                        } else {
                            // Only the two kinds above are subscribed to, so this
                            // is unreachable today — but a kind we skipped is not
                            // a kind we handled, and claiming otherwise tells
                            // Carbon the event is spent.
                            return OSStatus(eventNotHandledErr)
                        }
                        return noErr
                    }
                },
                buffer.count, buffer.baseAddress, opaque, &handler
            )
        }
        guard status == noErr else { return [:] }

        var results: [BindingID: Bool] = [:]
        var next: UInt32 = 1
        for id in BindingID.all {
            guard let binding = bindings[id] else {
                results[id] = false
                continue
            }
            let hotID = EventHotKeyID(signature: Self.signature, id: next)
            var ref: EventHotKeyRef?
            let registered = RegisterEventHotKey(
                binding.key.keyCode, binding.key.modifiers, hotID,
                GetApplicationEventTarget(), 0, &ref
            )
            if registered == noErr, let ref {
                refs[id] = ref
                ids[next] = id
                next += 1
            }
            // Answered from `refs`, not from `registered`, so this result, the
            // `registeredCount` the menu reports, and the repeat-call cache below
            // can never disagree about what is actually live.
            results[id] = refs[id] != nil
        }
        return results
    }

    func stop() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        ids.removeAll()
        // A held key whose release never arrives would leave the app stuck in a
        // hold, so clear the bookkeeping along with the registrations.
        pressedAt.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    // MARK: Dispatch

    /// Test seam: `--selftest` drives the dispatch path below without pressing a
    /// key, so it needs a Carbon id that resolves even when
    /// `RegisterEventHotKey` failed because another app owns the combination.
    /// Claims the next free id and returns it, which is why the caller uses the
    /// value rather than counting slots. Production ids come from `start()`.
    func testCarbonID(for id: BindingID) -> UInt32 {
        let next = (ids.keys.max() ?? 0) + 1
        ids[next] = id
        return next
    }

    /// `now` is `HotKeyCenter.uptime` in production and a literal in the
    /// self-test, so the duration arithmetic below can be proved without waiting
    /// on the clock.
    func handlePress(_ carbonID: UInt32, now: TimeInterval = HotKeyCenter.uptime) {
        guard let id = ids[carbonID] else { return }
        if pressedAt[id] != nil, HotKeyDecision.onAutoRepeat(id, nil) == nil {
            // Already down, so this is an auto-repeat. `nil` is the decision
            // layer's "change nothing", which drops the event and leaves the
            // original press time in place — re-stamping it would measure the
            // repeat instead of the hold and turn an intended hold into a tap.
            // The mode is passed as `nil` because a repeat carries no
            // mode-dependent information and `HotKeyCenter` has no access to the
            // user's mode; asking here keeps the one function that answers "what
            // should be active?" the only place the rule lives.
            return
        }
        // Recorded before `onPress` so a repeat that lands while the effect is
        // being applied is still dropped.
        pressedAt[id] = now
        onPress(id)
    }

    func handleRelease(_ carbonID: UInt32, now: TimeInterval = HotKeyCenter.uptime) {
        // `removeValue` returning nil means a release with no matching press: the
        // app launched while the key was down, or the press was swallowed. There
        // is no duration to measure, and clearing on a missing timestamp is how
        // an effect gets switched off by a key the user never pressed.
        guard let id = ids[carbonID], let start = pressedAt.removeValue(forKey: id) else {
            return
        }
        // Consumed, not just read: a second release for the same press has
        // nothing left to report and must not clear a freshly-applied effect.
        onRelease(id, now - start)
    }
}
