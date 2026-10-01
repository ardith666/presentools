# Customisable Hotkeys with Hold, Toggle, and Panic-Off

Date: 2026-09-30
Status: design approved, awaiting implementation plan

## Problem

Presentools ships four fixed global hotkeys — `⌘⌥0` (off), `⌘⌥1` (spotlight),
`⌘⌥2` (laser), `⌘⌥3` (zoom) — hardcoded in `HotKeyCenter`. Users cannot change
them, and there is no press-and-hold behaviour: every press switches to an effect
permanently until another key is pressed.

Three things are wanted:

1. **Customisable bindings.** Rebind each effect to any modifier + key
   combination, persisted across launches.
2. **Per-binding activation mode.** Each effect binding is either *hold*
   (momentary — active while the key is down) or *toggle* (sticky — press to
   turn on, press again to turn off).
3. **A panic key.** One combination that turns every effect off immediately,
   regardless of what is active. Default `⌥Esc`.

## Constraints

- Existing defaults must not move. `⌘⌥0`–`⌘⌥3` stay the shipped effect
  bindings, all in **hold** mode.
- Effect bindings must keep at least one of ⌘ or ⌥. A bare or Shift-only key is
  something the presentation app types, and grabbing it globally fights the deck.
  This is the same reasoning already recorded in `HotKeyCenter.bindings`.
- Bindings must not collide with each other or with well-known macOS shortcuts.
- The panic key defaults to `⌥Esc` rather than bare `Esc`, so that `Esc` keeps
  working in Keynote and PowerPoint. See "Why not bare Esc" below.
- No new permission prompts. Accessibility (TCC) access would make the whole
  feature fail silently for users who decline.

## Approach

Extend `HotKeyCenter` to also receive Carbon's `kEventHotKeyReleased` event.

Verified in the SDK headers
(`HIToolbox.framework/Headers/CarbonEvents.h:4714`):

```
kEventHotKeyReleased = 6
  --> kEventParamDirectObject (in, typeEventHotKeyID)
```

The release event carries the same `EventHotKeyID` payload as the press event,
so no second hotkey registration is needed. Carbon continues to own modifier
matching, conflict handling, and global delivery.

`CGEventTap` was considered and rejected: it would allow bare keys but requires
Accessibility permission, which is a poor trade for this feature.

## Why not bare Esc

`RegisterEventHotKey` does permit a zero modifier mask since macOS 10.3
(`CarbonEvents.h:15450`), so bare `Esc` is technically achievable without any
new permission.

It was rejected anyway. A bare binding claims the key from every application, so
`Esc` would stop working in Keynote and PowerPoint — and presenters use `Esc` to
leave fullscreen and to abort a slide show. `⌥Esc` gives the same one-keystroke
escape while leaving plain `Esc` untouched. It is listed in the recorder window
like any other binding, so a user who genuinely wants bare `Esc` can set it.

## Semantics

### Hold mode (default for all four effects)

| Action | On press | On release |
|--------|----------|------------|
| Tap (< 250 ms) | effect activates | effect **stays** active |
| Hold (≥ 250 ms) | effect activates | **all effects turn off** |

The effect applies on *press*, not after the 250 ms threshold, so there is no
latency. Duration is only consulted on *release*, to decide whether to commit
(tap) or clear (hold).

Clearing on release rather than restoring the previous effect was explicitly
chosen: releasing a hold leaves nothing active.

### Toggle mode

Press toggles that effect: if it is already active everything goes off,
otherwise it becomes the active effect. Release does nothing.

Auto-repeat must be suppressed here — a held key in toggle mode would otherwise
flicker the effect on and off.

### Panic key

Press turns every effect off immediately. It has no mode and no hold semantics;
its release does nothing.

### Held `off` binding

Holding the `.none` binding is a harmless no-op: it applies "off" on press, and
clearing on release is also "off".

## Architecture

### HotKeyCenter

Installs two event specs against the existing Carbon event handler:

- `kEventClassKeyboard / kEventHotKeyPressed`
- `kEventClassKeyboard / kEventHotKeyReleased`

New state:

```swift
private var pressedAt: [BindingID: Date] = [:]
```

The public callback becomes:

```swift
init(onPress: @escaping (BindingID) -> Void,
     onRelease: @escaping (BindingID, TimeInterval) -> Void)
```

Dispatch rules:

- **Pressed** — if `pressedAt[id]` is already set, this is auto-repeat; ignore it
  and do **not** reset the timestamp. Otherwise record `pressedAt[id] = now` and
  fire `onPress(id)`.
- **Released** — look up the press time. If there was no matching press, ignore
  it (a stray release, for example the app launched mid-hold). Otherwise remove
  the entry and fire `onRelease(id, duration)`.

A `HoldDetector` value type owns the 250 ms comparison so the tap/hold decision
is testable without Carbon.

### Effect application

`main.swift` owns the mapping from bindings to overlay state. Its handlers:

- **press, panic key** → apply `.none`
- **press, hold-mode binding** → apply that effect
- **press, toggle-mode binding** → if that effect is currently active apply
  `.none`, otherwise apply it
- **release, hold-mode binding, duration ≥ 250 ms** → apply `.none`
- **release, hold-mode binding, duration < 250 ms** → nothing
- **release, toggle-mode or panic key** → nothing

### Binding model

Replaces `HotKeyCenter.keyCodes` and `HotKeyCenter.modifiers`:

```swift
struct HotKeyBinding: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

enum ActivationMode: String {
    case hold
    case toggle
}

struct EffectBinding: Equatable {
    var key: HotKeyBinding
    var mode: ActivationMode
}

enum BindingID {
    case effect(Effect)   // .none, .spotlight, .laser, .zoom
    case panic
}
```

Defaults, unchanged from today:

| Binding | keyCode | modifiers | mode |
|---------|---------|-----------|------|
| `.effect(.none)` | `kVK_ANSI_0` (0x1D) | `cmdKey \| optionKey` | hold |
| `.effect(.spotlight)` | `kVK_ANSI_1` (0x12) | `cmdKey \| optionKey` | hold |
| `.effect(.laser)` | `kVK_ANSI_2` (0x13) | `cmdKey \| optionKey` | hold |
| `.effect(.zoom)` | `kVK_ANSI_3` (0x14) | `cmdKey \| optionKey` | hold |
| `.panic` | `kVK_Escape` (0x35) | `optionKey` | — |

### Persistence

`Settings` gains keys storing key code and modifier mask as separate `Int`s, so
a partial write cannot corrupt a binding, plus a raw-value string for the mode:

```
hotkey.<id>.keyCode
hotkey.<id>.modifiers
hotkey.<id>.mode        // effect bindings only
```

`reset()` restores all five defaults.

### Recorder window

`NSMenu` cannot capture arbitrary key combinations, so the status menu gains a
**Shortcuts…** item that opens a standalone `NSWindow` (~380×280):

- Five rows: Off, Spotlight, Laser, Zoom, Panic (All Off).
- Each row shows its current combination, and the four effect rows carry an
  `NSPopUpButton` for Hold / Toggle. The panic row has no popup.
- Clicking a combination makes that row first responder and shows "Press keys…".
- `flagsChanged` updates the modifier glyphs as they are pressed.
- `keyDown` completes the binding, after the conflict rules below are checked.
- `Esc` cancels recording, `Delete` / `Backspace` clears a binding.
- A **Reset** button restores the shipped defaults.

Clearing an effect binding is allowed. That effect then has no keyboard shortcut
and is reachable only from the status menu, and the panel shows its row as
`— not set —`. Clearing the panic key is allowed too; the app simply has no
one-keystroke escape, and the panel says so.

**The window must call `HotKeyCenter.stop()` on open and `start()` on close.**
Without this, recording `⌘⌥1` would fire Spotlight through the still-active
global hotkey. This is the one non-obvious requirement in the feature.

### Conflict rules

A candidate combination is rejected — keeping the previous binding — when:

1. It duplicates any other binding in the table, including the panic key.
2. It matches a denylist of common macOS shortcuts: `⌘Space`, `⌘Tab`, `⌘Q`,
   `⌘W`, `⌘H`, `⌘M`, ``⌘` ``, `⌘,`, `⌘/`, `⌘+`, `⌘-`, `⌥Tab`, `⌃Space`, and any
   F-key without a ⌘ or ⌥ modifier.
3. It is an **effect** binding with neither ⌘ nor ⌥.

The panic key is exempt from rule 3, so a user can bind it to bare `Esc` if
they accept losing `Esc` elsewhere. Rule 2 always applies.

Rejections name the specific reason, e.g. `⌘Tab is used by macOS — pick another`.

## Error handling

`RegisterEventHotKey` failing means another app owns the combination. That is
not fatal — the other bindings keep working. `HotKeyCenter` reports per-binding
registration status rather than only a count, and the recorder window marks an
unregistered row in place so the user can see which bindings did not take.

Registration is re-run after any binding change.

## Testing

### Automated (`--selftest`)

- `HoldDetector`: duration below, at, and above 250 ms.
- Effect application decisions: tap-hold / hold-hold / toggle-on / toggle-off /
  panic, driven through a pure function so no overlay is required.
- Binding serialisation round-trips through `UserDefaults` for all five bindings,
  including a modified combination and a non-default mode.
- A non-default binding survives a `Settings` re-read.
- Conflict detection: internal duplicate rejected, each denylisted shortcut
  rejected, Shift-only and bare effect bindings rejected, bare `Esc` accepted
  for the panic key only.
- `HotKeyCenter.start()` reports 5/5 registered under the defaults.

### Manual (Mac mini)

- Tap `⌘⌥1` → spotlight on and stays on after release.
- Hold `⌘⌥2` → laser on while held, all effects off after release.
- Hold through a slow 2 s press to confirm no auto-repeat misbehaviour and that
  exactly one release is delivered.
- Switch a binding to toggle mode, tap twice, confirm on/off/on.
- Press `⌥Esc` with an effect active, confirm everything clears.
- Confirm plain `Esc` still works in Keynote.
- Record a custom binding, quit, relaunch, confirm it persisted.
- Assign a combination another app owns, confirm the row is flagged.

The auto-repeat and exactly-one-release behaviours are properties of the Carbon
runtime, not of the headers, so they can only be proven with real key input.

## Implementation phases

The feature is cohesive but large enough that it should land in two verified
steps rather than one:

1. **Semantics** — `BindingID`, `HoldDetector`, per-binding `ActivationMode`,
   the panic key, and the pure effect-application decision function. Fully
   covered by `--selftest` with the existing hardcoded bindings. No UI change.
2. **Persistence and recorder window** — `Settings` keys, the recorder
   `NSWindow`, conflict rules, per-binding registration status, re-registration
   on change.

Phase 1 is useful on its own: hold, toggle, and panic all work on the shipped
`⌘⌥0`–`⌘⌥3` bindings before any customisation UI exists.

## Out of scope

- Bare keys for effect bindings (rejected: conflicts with typing). Bare keys for
  the panic key are allowed.
- Sequences or chords.
- Per-display or per-application profiles.
- Import/export of binding sets.

## Risks

| Risk | Mitigation |
|------|------------|
| Carbon auto-repeats `Pressed` while held, restarting the duration timer or flickering toggle mode | Guard against re-entry in the press handler; verified by the manual hold test |
| A `Released` event never arrives, leaving the app stuck in a hold | Resolve any pending press before applying a new one, and clear `pressedAt` in `stop()` |
| Modified keys registered by other apps silently win | Report per-binding registration status in the recorder window |
| A panic key bound to bare `Esc` surprises the user by breaking `Esc` elsewhere | Panic row is labelled "All Off" and the exemption from the modifier rule is stated in the panel |