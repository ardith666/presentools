import AppKit

/// The settings editor: a sidebar of sections on the left, sliders on the right.
///
/// An `NSPanel` rather than an `NSWindow`, and `.nonactivatingPanel` rather than
/// plain activation: the presenter is usually looking at Keynote or PowerPoint,
/// so taking app focus to change a radius would take the slide away.
/// `becomesKeyOnlyIfNeeded` lets the panel take key status only when a control
/// inside it actually needs it.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static let sidebarWidth: CGFloat = 148
    private static let rowHeight: CGFloat = 28
    private static let labelWidth: CGFloat = 74
    private static let readoutWidth: CGFloat = 62
    private static let contentSize = NSSize(width: 470, height: 268)
    private static let frameKey = "settingsWindowFrame"

    private let currentEffect: () -> Effect
    private let setEffect: (Effect) -> Void
    private let resetAll: () -> Void

    /// The effect that was running before a slider forced a different one on.
    /// `nil` means this window has not changed the effect, so closing it changes
    /// nothing.
    private var previewRestore: Effect?
    /// Live controls for the visible section, so a value change can refresh a
    /// readout without rebuilding the pane under the slider being dragged.
    private var controls: [Control] = []
    private var swatches: [(button: NSButton, preset: (name: String, color: NSColor))] = []
    private var currentSection = 0

    private var window: NSPanel!
    private var table: NSTableView!
    private var pane: NSStackView!
    private var titleLabel: NSTextField!

    /// A slider, the label that tracks it, and the spec it came from — the
    /// action looks the spec up by identity, never by matching values, because
    /// two sliders in one section can legitimately hold the same number.
    private struct Control {
        let spec: SliderSpec
        let slider: NSSlider
        let readout: NSTextField
    }

    init(
        currentEffect: @escaping () -> Effect,
        setEffect: @escaping (Effect) -> Void,
        resetAll: @escaping () -> Void
    ) {
        self.currentEffect = currentEffect
        self.setEffect = setEffect
        self.resetAll = resetAll
        super.init()
        build()
    }

    func show() {
        // Values may have moved while the panel was closed — a hotkey, a reset,
        // or a change made while this window was never open. Re-read before
        // showing rather than trusting what the controls last held.
        if table.selectedRow < 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        showSection(max(table.selectedRow, 0))
        window.orderFront(nil)
    }

    private func build() {
        let saved = UserDefaults.standard.string(forKey: Self.frameKey).flatMap(NSRectFromString)
        let panel = NSPanel(
            contentRect: saved ?? NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Presentools Settings"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        // Otherwise the panel lands on whichever Space was active at launch and
        // disappears the moment the presenter moves to the next slide deck.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        if saved == nil { panel.center() }
        window = panel

        guard let content = panel.contentView else { return }

        // A plain horizontal stack rather than an `NSSplitView`. The sidebar is
        // pinned to a fixed width and the divider is not draggable, so the split
        // view buys nothing — and it assigns its own subview frames, which wins
        // against the constraints below and left both panes full-width and
        // overlapping.
        let split = NSStackView()
        split.orientation = .horizontal
        split.alignment = .top
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        let sidebar = NSScrollView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.hasVerticalScroller = false
        sidebar.drawsBackground = false
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
        table.rowHeight = Self.rowHeight
        table.headerView = nil
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        sidebar.documentView = table
        split.addArrangedSubview(sidebar)
        self.table = table

        let pane = NSStackView()
        pane.orientation = .vertical
        pane.alignment = .leading
        pane.spacing = 12
        pane.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(pane)
        self.pane = pane

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
        let reset = NSButton(
            title: "Reset to Defaults",
            target: self,
            action: #selector(resetTapped(_:))
        )
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let footer = NSStackView(views: [titleLabel, spacer, reset])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)
        self.titleLabel = titleLabel

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            // The pane above and this footer below share the content height and
            // nothing says which one gets the slack, so Auto Layout hands all of
            // it to the footer and the sidebar collapses to zero height. One row.
            footer.heightAnchor.constraint(lessThanOrEqualToConstant: 30),
            reset.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
        ])
    }

    // MARK: Sections

    private func section(at index: Int) -> SliderSection? {
        SliderSection.all.indices.contains(index) ? SliderSection.all[index] : nil
    }

    /// Rebuilds the right pane for one section. Called on selection change and on
    /// open — never per slider tick, which would replace the control mid-drag.
    private func showSection(_ index: Int) {
        guard let section = section(at: index) else { return }
        currentSection = index
        for view in pane.arrangedSubviews {
            pane.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        controls = []
        swatches = []
        titleLabel.stringValue = section.title

        for spec in section.sliders {
            let (row, control) = sliderRow(spec)
            controls.append(control)
            pane.addArrangedSubview(row)
        }
        if section.colorKeyPath != nil, !section.colorPresets.isEmpty {
            pane.addArrangedSubview(colorRow(section))
        }
    }

    private func sliderRow(_ spec: SliderSpec) -> (view: NSView, control: Control) {
        let label = NSTextField(labelWithString: spec.label)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false

        // Continuous so the overlay repaints per tick during a drag instead of
        // on mouse-up: `Settings.set` notifies `settingsChanged()` synchronously.
        let slider = NSSlider(
            value: Double(spec.value()),
            minValue: Double(spec.range.lowerBound),
            maxValue: Double(spec.range.upperBound),
            target: self,
            action: #selector(sliderMoved(_:))
        )
        slider.isContinuous = true
        slider.allowsTickMarkValuesOnly = false
        slider.doubleValue = Self.snap(slider.doubleValue, to: spec.step)
        slider.translatesAutoresizingMaskIntoConstraints = false

        let readout = NSTextField(labelWithString: spec.format(spec.value()))
        readout.alignment = .right
        readout.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular
        )
        readout.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, slider, readout])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: Self.labelWidth),
            readout.widthAnchor.constraint(equalToConstant: Self.readoutWidth),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        return (row, Control(spec: spec, slider: slider, readout: readout))
    }

    private func colorRow(_ section: SliderSection) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        for (index, preset) in section.colorPresets.enumerated() {
            let button = NSButton(
                image: swatch(preset.color), target: self, action: #selector(pickColor(_:))
            )
            button.tag = index
            button.toolTip = preset.name
            swatches.append((button, preset))
            row.addArrangedSubview(button)
        }
        refreshSwatches()
        return row
    }

    // MARK: Actions

    @objc private func sliderMoved(_ sender: NSSlider) {
        guard let control = controls.first(where: { $0.slider === sender }) else { return }
        activatePreview()
        let spec = control.spec
        // A raw drag reports fractions of a step; the readout has to show a
        // value the user can reproduce from the stored setting.
        let snapped = Self.snap(sender.doubleValue, to: spec.step)
        sender.doubleValue = snapped
        spec.apply(CGFloat(snapped))
        control.readout.stringValue = spec.format(CGFloat(snapped))
    }

    @objc private func pickColor(_ sender: NSButton) {
        guard let section = section(at: currentSection),
              let keyPath = section.colorKeyPath,
              section.colorPresets.indices.contains(sender.tag)
        else { return }
        Settings.shared.set(keyPath, section.colorPresets[sender.tag].color)
        refreshSwatches()
    }

    @objc private func resetTapped(_ sender: Any?) {
        resetAll()
        showSection(currentSection)
    }

    // MARK: Preview

    /// Brings on the effect this section needs, once. Guarded on "not already
    /// the current effect" so a drag does not call `set(_:)` per tick, and
    /// `set(_:)` rebuilds the menu bar every time.
    private func activatePreview() {
        guard let section = section(at: currentSection) else { return }
        let current = currentEffect()
        let target = section.previewEffect(current: current)
        guard target != current else { return }
        if previewRestore == nil { previewRestore = current }
        setEffect(target)
    }

    func windowWillClose(_ notification: Notification) {
        if let restore = previewRestore {
            setEffect(restore)
            previewRestore = nil
        }
        // `contentView` rather than `frame`: this is stored as a content rect
        // and read back into `contentRect:`, and mixing the two would drift by
        // the title bar height on every open.
        if let content = window.contentView {
            UserDefaults.standard.set(NSStringFromRect(content.frame), forKey: Self.frameKey)
        }
    }

    // MARK: Helpers

    private static func snap(_ v: Double, to step: CGFloat) -> Double {
        (v / Double(step)).rounded() * Double(step)
    }

    private func refreshSwatches() {
        guard let keyPath = section(at: currentSection)?.colorKeyPath else { return }
        let current = Settings.shared[keyPath: keyPath]
        for (button, preset) in swatches {
            button.state = preset.color.hexString == current.hexString ? .on : .off
        }
    }

    private func swatch(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    // MARK: Sidebar

    func numberOfRows(in tableView: NSTableView) -> Int { SliderSection.all.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // A plain transparent label rather than a reused `NSTableCellView`: the
        // `.sourceList` highlight is drawn by the table behind the view, so a
        // label lets it show through and there is nothing to recycle.
        let label = NSTextField(labelWithString: SliderSection.all.indices.contains(row)
            ? SliderSection.all[row].title
            : "")
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showSection(table.selectedRow)
    }
}