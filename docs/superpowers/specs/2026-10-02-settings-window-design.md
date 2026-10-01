# Presentools — settings window with live-preview sliders

Replace the four stepper submenus in the menu bar with a single interactive
settings window: a sidebar of sections, continuous sliders per parameter, and
numbers that update as the slider moves.

## Context

The menu bar currently builds four submenus — Spotlight, Zoom Lens, Laser
Pointer, Edge — and each tunable inside them is a *stepper pair*: a
`Larger`/`Smaller` row, then a disabled line carrying the current value
(`main.swift:268`). Six values are stepped this way across four sections:

| Section | Stepper pair | Step | Range |
|---|---|---|---|
| Spotlight | `Circle: 190 pt` | ±20 | 80–400 |
| Spotlight | `Darkness: 82%` | ±0.06 | 0.2–0.98 |
| Zoom Lens | `Lens: 460 pt` | ±80 | 180–900 |
| Zoom Lens | `Magnify: 2.0x` | ±0.5 | 1.5–6 |
| Laser Pointer | `Dot: 18 pt` | ±1 | 3–26 |
| Edge | `Line: 3 pt` | ±1 | 0–12 |

Getting to a specific value means opening a submenu and clicking the same row
several times. `spotlightDim` at 0.06 per click is 13 clicks to cross its
whole range. The values also cannot be *seen* changing: `settingsChanged()`
already repaints immediately, but a stepper only gives one value per click, so
the live preview is invisible during adjustment.

The user asked for these values as sliders that preview live as they change.

## Why a window, not sliders in the menu

`NSMenu` has no native slider support. A real `NSSlider` would have to be
embedded via `NSMenuItem.view`, inside the modal tracking loop that
`NSMenu` runs while open. Slider drags inside that loop are unreliable: the
loop consumes mouse events for menu tracking, and drag gestures get swallowed
or the menu closes mid-drag. The `ShortcutRecorderWindow` panel already
exercises exactly this hazard — `checkRecorderHitTesting()` exists only because
a panel that opens but cannot be clicked passes every other check.

A window is also the only shape that can carry a sidebar. Four sections with
six sliders plus two colour pickers does not fit in a menu bar without
nesting three levels deep.

The cost of a window is that it can sit over the slide. The existing design
avoids that deliberately — the comment on `addSettings` says settings live in
the menu "so every value is reachable without a window ever appearing over the
slide" (`main.swift:265`). This design keeps that promise by making the window
non-activating and transient rather than by refusing a window.

## Decision: non-activating panel, floating level

`SettingsWindow` is an `NSPanel`, not an `NSWindow`:

- `styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel]`
- `becomesKeyOnlyIfNeeded = true` — the panel takes key status only when a
  control in it needs it, so opening Settings never takes focus away from
  Keynote, PowerPoint, or the browser the presenter is reading from
- `level = .floating` so it stays above a fullscreen slide
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` so it
  follows the presenter across spaces and stays reachable over
  `.fullScreenAuxiliary` content

`isFloatingPanel` is set so the panel joins the window cycle properly, and the
window is not released on close — one instance, shown and hidden.

Frame is persisted in `UserDefaults` under `settingsWindowFrame` and restored
on open, so the presenter places it once. A panel whose position resets on
every open is a panel that gets closed instead.

## Decision: the menu bar keeps exactly one item

`addSettings` collapses to a single `Settings…` item. `Reset to Defaults` moves
into the window's footer — it is a destructive bulk action, not something
that belongs in a menu bar that is supposed to stay terse, and leaving it
behind would mean the window is not the place to look for settings.

The `Adjust` enum, `addStepper`, `adjustItem`, `adjust(_:)`, `addColors`, and
`submenu(_:_:)` become dead and are deleted (~165 lines). `Settings.points`
and the `swatch(_:)` helper survive, relocated into the window.

## Layout

`NSSplitView`, left sidebar and right pane:

- **Sidebar** — `NSTableView`, single column, no header, 28pt rows, selection
  highlight on. Four rows in order: Spotlight, Zoom Lens, Laser Pointer, Edge.
  Data source is a plain array of `SliderSpec` sections.
- **Pane** — rebuilt per selection from that section's specs. Each numeric spec
  renders one row: a fixed-width label, an `NSSlider` (`isContinuous = true`),
  and a monospaced-digit readout. Colour specs render as a row of preset
  swatch buttons, the same presets and the same `.on`/`.off` state check the
  menu used.
- **Footer** — `Reset to Defaults`, plus a section title as static text.

The window opens on Spotlight. Content is rebuilt on selection change, not on
every value change, so a slider being dragged does not rebuild the view that
owns it. The readout `NSTextField` is the only thing updated per tick.

## Live preview

Already wired, and no new plumbing is needed:

```
NSSlider (isContinuous = true)
  → Settings.set(_:_:)              // Settings.swift:265
  → onChange?()                     // Settings.swift:267
  → settingsChanged()               // main.swift:386
  → lens.applySize() + overlays repaint
```

`isContinuous = true` makes the slider fire its action on every movement during
a drag rather than on mouse-up, so the overlay repaints per tick.

`didSet` on each `Settings` property persists to `UserDefaults`, so a drag
writes at drag rate. That is coalesced by `cfprefsd` and cheap, and the value
has to survive a crash mid-drag, so no debounce is added.

## Auto-preview when the effect is not on screen

A slider preview is only visible if that effect is active. Moving the
`Darkness` slider with the laser showing would repaint a spotlight nobody is
looking at. `SettingsWindow` therefore owns a `previewRestore: Effect?`:

- On the first slider move in a section, if the section's preview effect is not
  the current effect: save the current effect into `previewRestore`, then call
  the host's `set(_:)`.
- Activation is guarded by "not already the current effect", so it happens once
  per section per open rather than per tick. Dragging does not spam
  `set(_:)`, which calls `rebuildMenu()`.
- On window close: if `previewRestore` is set, restore it and clear it.

The host is injected rather than reached for, so `SettingsWindow` does not own
the effect state:

```swift
SettingsWindow(
    currentEffect: { [weak self] in self?.effect ?? .none },
    setEffect: { [weak self] next in self?.set(next) },
    resetAll: { [weak self] in self?.resetSettings(nil) }
)
```

`set(_:)` already requests Screen Recording permission for `.zoom`
(`main.swift:403`), so previewing the lens on a fresh install prompts rather
than failing silently.

`Edge` is the awkward case. The ring is shared by the spotlight and the lens —
one setting for both, deliberately (`main.swift:303`) — so `Edge` has no effect
of its own to activate. Its preview effect is resolved: whichever of
`.spotlight`/`.zoom` is already active, falling back to `.spotlight`. Dragging
`Line` while the laser is showing therefore brings up the spotlight, and closing
the window puts the laser back.

## Slider specs: the testable part

`SliderSpec` is a pure value — a keypath, a range, a step, a readout format —
with no AppKit in it:

```swift
struct SliderSpec {
    let label: String
    let keyPath: ReferenceWritableKeyPath<Settings, CGFloat>
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let format: (CGFloat) -> String
}
```

Ranges are copied verbatim from the clamps being deleted, so no reachable
value narrows:

| Section | Spec | Range | Step |
|---|---|---|---|
| Spotlight | `Circle` `\.spotlightRadius` | 80–400 | 1 |
| Spotlight | `Darkness` `\.spotlightDim` | 0.2–0.98 | 0.01 |
| Zoom Lens | `Lens` `\.lensSide` | 180–900 | 1 |
| Zoom Lens | `Magnify` `\.lensMagnification` | 1.5–6 | 0.05 |
| Laser Pointer | `Dot` `\.laserRadius` | 3–26 | 0.1 |
| Edge | `Line` `\.ringWidth` | 0–12 | 0.1 |

Steps are finer than the old steppers because a slider has no per-click cost to
amortise.

`SliderSection` groups a title, its specs, its colour presets, and the preview
effect. `SliderSection.all` is the single source of truth — the sidebar, the
pane, and the tests all read it, so a section cannot exist in the sidebar and
be missing its sliders.

## Readout formatting

`Settings.points` already exists (`Settings.swift:144`) and carries units, so
it is reused for the three point-valued specs. Two new formats:

- Darkness is a percentage: `Int(v * 100)%`
- Magnify is one decimal with a trailing `x`: `String(format: "%.1f", v) + "x"`

## Tests

Added to `SelfTest.run()` in the existing style — one pure function per concern,
`expect(_:_:)` printing `ok`/`BAD`, all of it AppKit-free so it holds in
`--selftest` without a window server:

- **defaults in range** — every spec's range contains the shipped `Default`
  value. A range typo that strands the default fails here instead of snapping
  the slider to an end on first open.
- **clamping** — a pure `clamped(_:)` on `SliderSpec` returns the low bound
  below the range, the high bound above it, and the value inside.
- **formatting** — `Settings.points` and both new formats for known inputs.
- **effect coverage** — the four effects are reachable as preview effects, and
  every numeric `Settings` property appears in exactly one spec. This is the
  check that catches a mistyped keypath or a value left behind in a menu that
  no longer exists.

Window behaviour itself is not unit-tested. `checkRecorderHitTesting()` is the
precedent for hit-testing a panel, but the values under test are pixels a human
judges better; the pixel checks already cover repaint correctness, and
`settingsChanged()` is unchanged.

## Scope

Not included: presets of whole looks, dragging sliders to a live presentation
over a second display, remembering the selected section, and a colour panel
beyond the existing presets.