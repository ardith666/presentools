import AppKit

/// One tunable number, described without reference to any control.
///
/// AppKit-free apart from `CGFloat`, so the range, step, and readout format are
/// all checkable in `--selftest` without a window server.
@MainActor
struct SliderSpec {
    let label: String
    let keyPath: ReferenceWritableKeyPath<Settings, CGFloat>
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let format: @MainActor (CGFloat) -> String

    func clamped(_ v: CGFloat) -> CGFloat {
        min(max(v, range.lowerBound), range.upperBound)
    }

    func value() -> CGFloat {
        Settings.shared[keyPath: keyPath]
    }

    func apply(_ v: CGFloat) {
        Settings.shared.set(keyPath, clamped(v))
    }
}

/// A sidebar section: sliders, optional colour presets, and the effect that has
/// to be on screen before a slider move is visible.
@MainActor
struct SliderSection {
    let title: String
    let sliders: [SliderSpec]
    let colorKeyPath: ReferenceWritableKeyPath<Settings, NSColor>?
    let colorPresets: [(name: String, color: NSColor)]
    /// Which effect this section previews onto, given what is running now.
    ///
    /// Usually that is the section's own effect. The shared ring is the exception:
    /// it belongs to the spotlight and the lens alike, so the Edge section has no
    /// effect of its own: it previews onto whichever of those is already up, and
    /// falls back to the spotlight when neither is.
    let preview: (Effect) -> Effect

    func previewEffect(current: Effect) -> Effect {
        preview(current)
    }

    /// Every numeric setting, in sidebar order. The window and the tests both
    /// read this list, so a section cannot appear in the sidebar without its
    /// sliders.
    static let all: [SliderSection] = [
        SliderSection(
            title: "Spotlight",
            sliders: [
                SliderSpec(
                    label: "Circle", keyPath: \.spotlightRadius,
                    range: 80...400, step: 1, format: Settings.points
                ),
                SliderSpec(
                    label: "Darkness", keyPath: \.spotlightDim,
                    range: 0.2...0.98, step: 0.01, format: Self.percent
                ),
            ],
            colorKeyPath: nil,
            colorPresets: [],
            preview: { _ in .spotlight }
        ),
        SliderSection(
            title: "Zoom Lens",
            sliders: [
                SliderSpec(
                    label: "Lens", keyPath: \.lensSide,
                    range: 180...900, step: 1, format: Settings.points
                ),
                SliderSpec(
                    label: "Magnify", keyPath: \.lensMagnification,
                    range: 1.5...6, step: 0.05, format: Self.magnify
                ),
            ],
            colorKeyPath: nil,
            colorPresets: [],
            preview: { _ in .zoom }
        ),
        SliderSection(
            title: "Laser Pointer",
            sliders: [SliderSpec(
                label: "Dot", keyPath: \.laserRadius,
                range: 3...26, step: 0.1, format: Self.points
            )],
            colorKeyPath: \.laserColor,
            colorPresets: Settings.laserPresets,
            preview: { _ in .laser }
        ),
        SliderSection(
            title: "Edge",
            sliders: [SliderSpec(
                label: "Line", keyPath: \.ringWidth,
                range: 0...12, step: 0.1, format: Self.points
            )],
            colorKeyPath: \.ringColor,
            colorPresets: Settings.ringPresets,
            preview: { current in (current == .spotlight || current == .zoom) ? current : .spotlight }
        ),
    ]

    static func percent(_ v: CGFloat) -> String { "\(Int((v * 100).rounded()))%" }

    static func magnify(_ v: CGFloat) -> String { String(format: "%.1f", v) + "x" }

    static func points(_ v: CGFloat) -> String { String(format: "%.1f pt", v) }
}
