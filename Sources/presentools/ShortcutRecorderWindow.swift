import AppKit

/// Editor for the binding table. An `NSMenu` cannot do this job: `keyEquivalent`
/// takes one key plus modifiers, there is nowhere to draw "Press keys…", and the
/// menu would have to close before the user could press anything.
///
/// The caller must stop the global hotkeys before calling `show()` and restart
/// them on commit. Without that, recording `⌥1` fires Spotlight through the
/// still-registered hotkey instead of being recorded.
@MainActor
final class ShortcutRecorderWindow: NSObject, NSWindowDelegate {
    private static let rowHeight: CGFloat = 30
    private static let setButtonWidth: CGFloat = 52

    private var bindings: [BindingID: EffectBinding]
    private let onCommit: ([BindingID: EffectBinding]) -> Void

    private var window: NSWindow!
    /// `rows_map` is the authoritative store: `build()` runs from `init` before any
    /// other method can be reached, so both start empty and stay in step.
    private var rows: [BindingID: Row] = [:]
    private var statusLabel: NSTextField!
    private var recorder: Recorder!
    private var recording: BindingID?

    /// One binding line: name, current combination, activation mode, and the
    /// button that starts recording. The mode popup is hidden for the panic
    /// binding, which acts on press and has no mode to choose.
    private final class Row: NSView {
        let id: BindingID
        let name = NSTextField(labelWithString: "")
        let value = NSTextField(labelWithString: "")
        let mode = NSPopUpButton()
        let button = NSButton()

        init(id: BindingID, hasMode: Bool) {
            self.id = id
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            name.stringValue = id.title
            name.font = .systemFont(ofSize: 13)
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            value.alignment = .right
            value.textColor = .labelColor
            mode.addItems(withTitles: ActivationMode.allCases.map(\.rawValue))
            mode.controlSize = .small
            mode.isHidden = !hasMode
            button.title = "Set…"
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.setAccessibilityLabel("Set shortcut for \(id.title)")
            for subview in [name, value, mode, button] {
                // Without this the constraints below are inert and every control
                // stays 0x0 at the row origin — the panel looked right but nothing
                // inside it had a hit area to click.
                subview.translatesAutoresizingMaskIntoConstraints = false
                addSubview(subview)
            }
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: leadingAnchor),
                name.centerYAnchor.constraint(equalTo: centerYAnchor),
                mode.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 190),
                mode.centerYAnchor.constraint(equalTo: centerYAnchor),
                mode.widthAnchor.constraint(equalToConstant: 78),
                button.leadingAnchor.constraint(equalTo: mode.trailingAnchor, constant: 10),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: ShortcutRecorderWindow.setButtonWidth),
                value.trailingAnchor.constraint(equalTo: mode.leadingAnchor, constant: -10),
                value.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unused") }
    }

    /// Captures one combination. It has to be a real view in the window hierarchy
    /// to hold first responder status, which is why it is added to the content
    /// view rather than used as a free-floating responder override.
    ///
    /// `NSEvent.keyCode` is already the ANSI virtual key code, which is exactly
    /// what `RegisterEventHotKey` wants, so capture needs no lookup table.
    private final class Recorder: NSView {
        var onKey: ((HotKeyBinding) -> Void)?
        var onCancel: (() -> Void)?
        var onClear: (() -> Void)?
        var onModifiers: ((UInt32) -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { true }

        /// Mouse-transparent, keyboard-active.
        ///
        /// The recorder must be a real view in the window to hold first
        /// responder, so it is pinned over the whole content rect. AppKit hit-tests
        /// subviews in reverse add order and a plain `NSView` does not opt out, so
        /// without this it sat on top of the whole panel and ate every click on
        /// the "Set…" buttons and the mode popups — the panel opened, looked
        /// correct, and nothing in it could be selected. Returning `nil` sends
        /// the click down to whatever is actually underneath while leaving
        /// `makeFirstResponder` untouched.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Modifier-only press. Nothing to record yet, but the row should show the
        /// glyphs so the user can see ⌥ land before the final key.
        override func flagsChanged(with event: NSEvent) {
            onModifiers?(HotKeyBinding.modifierMask(from: event))
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 53:  // esc
                onCancel?()
            case 51, 117:  // delete, forward delete
                onClear?()
            default:
                onKey?(HotKeyBinding(
                    keyCode: UInt32(event.keyCode),
                    modifiers: HotKeyBinding.modifierMask(from: event)
                ))
            }
        }
    }

    // MARK: Lifecycle

    init(bindings: [BindingID: EffectBinding], onCommit: @escaping ([BindingID: EffectBinding]) -> Void) {
        self.bindings = bindings
        self.onCommit = onCommit
        super.init()
        build()
    }

    /// Clears the delegate so a closed window does not retain this object
    /// through the window server's reference. `window` is already nil by then
    /// in the normal close path; this is for the app tearing down.
    func releaseWindow() {
        window.delegate = nil
        window.contentView = nil
        window = nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let ids = BindingID.all
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: CGFloat(ids.count) * Self.rowHeight + 96),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Presentools Shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        guard let content = window.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for (index, id) in ids.enumerated() {
            // The panic binding acts on press and ignores its release, so it has
            // no mode to choose.
            let hasMode: Bool
            if case .effect = id { hasMode = true } else { hasMode = false }
            let row = Row(id: id, hasMode: hasMode)
            row.value.stringValue = Self.label(for: bindings[id]?.key)
            if let mode = bindings[id]?.mode,
               let index = ActivationMode.allCases.firstIndex(of: mode) {
                row.mode.selectItem(at: index)
            }
            row.mode.target = self
            row.mode.action = #selector(modeChanged(_:))
            row.button.tag = index
            row.button.target = self
            row.button.action = #selector(record(_:))
            row.widthAnchor.constraint(equalToConstant: 380).isActive = true
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            rows[id] = row
            stack.addArrangedSubview(row)
        }

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let reset = NSButton(title: "Reset to defaults", target: self, action: #selector(resetToDefaults(_:)))
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        let done = NSButton(title: "Done", target: self, action: #selector(commitAndClose(_:)))
        done.bezelStyle = .rounded
        done.controlSize = .small
        done.keyEquivalent = "\r"

        let buttons = NSStackView(views: [statusLabel, NSView(), reset, done])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        recorder = Recorder()
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.onKey = { [weak self] key in
            guard let self, let id = self.recording else { return }
            self.accept(key, for: id)
        }
        recorder.onCancel = { [weak self] in
            guard let self, let id = self.recording else { return }
            self.stopRecording(id)
        }
        recorder.onClear = { [weak self] in
            guard let self, let id = self.recording else { return }
            self.bindings[id] = nil
            self.stopRecording(id)
        }
        recorder.onModifiers = { [weak self] mask in
            guard let self, let id = self.recording else { return }
            self.rows[id]?.value.stringValue = HotKeyConflict.describe(
                HotKeyBinding(keyCode: HotKeyBinding.glyphPreviewKeyCode, modifiers: mask)
            )
        }
        content.addSubview(recorder)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 170),
            // The recorder is invisible; it just needs to be in the hierarchy and
            // able to grow to the window so it can take first responder status.
            recorder.topAnchor.constraint(equalTo: content.topAnchor),
            recorder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            recorder.widthAnchor.constraint(equalTo: content.widthAnchor),
            recorder.heightAnchor.constraint(equalTo: content.heightAnchor),
        ])
    }

    

    // MARK: Actions

    @objc private func record(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < BindingID.all.count else { return }
        let id = BindingID.all[sender.tag]
        recording = id
        statusLabel.stringValue = ""
        rows[id]?.value.stringValue = "Press keys…"
        window.makeFirstResponder(recorder)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let row = rows.values.first(where: { $0.mode === sender }),
              let mode = ActivationMode(rawValue: sender.titleOfSelectedItem ?? "") else { return }
        // A cleared row has nothing to change the mode of; the popup shows hold
        // until a key is recorded, so writing the default back is harmless and
        // keeps the model and the popup in agreement.
        var binding = bindings[row.id] ?? EffectBinding(
            key: HotKeyBinding.Defaults.bindings[row.id]?.key
                ?? HotKeyBinding(keyCode: 0, modifiers: 0),
            mode: .hold
        )
        binding.mode = mode
        bindings[row.id] = binding
    }

    @objc private func resetToDefaults(_ sender: Any?) {
        bindings = HotKeyBinding.Defaults.bindings
        for (id, row) in rows { refresh(row, binding: bindings[id]) }
        statusLabel.stringValue = ""
    }

    @objc private func commitAndClose(_ sender: Any?) {
        onCommit(bindings)
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing with the title bar button is a commit like any other: the panel
        // has no other way to save, and discarding silently would lose edits.
        onCommit(bindings)
        return true
    }

    // MARK: Helpers

    /// A rejected combination keeps the previous binding. Returning a reason the
    /// user can act on is the whole point — a silently ignored keystroke looks
    /// like a broken app.
    private func accept(_ key: HotKeyBinding, for id: BindingID) {
        defer { window.makeFirstResponder(nil) }
        if let reason = HotKeyConflict.reason(for: key, id: id, in: bindings) {
            statusLabel.stringValue = reason
            statusLabel.textColor = .systemRed
            refresh(rows[id], binding: bindings[id])
            recording = nil
            return
        }
        var binding = bindings[id] ?? EffectBinding(key: key, mode: .hold)
        binding.key = key
        bindings[id] = binding
        statusLabel.stringValue = ""
        recording = nil
        refresh(rows[id], binding: binding)
    }

    private func stopRecording(_ id: BindingID) {
        recording = nil
        refresh(rows[id], binding: bindings[id])
        window.makeFirstResponder(nil)
    }

    private func refresh(_ row: Row?, binding: EffectBinding?) {
        row?.value.stringValue = Self.label(for: binding?.key)
    }

    static func label(for key: HotKeyBinding?) -> String {
        guard let key else { return "— not set —" }
        return HotKeyConflict.describe(key)
    }

    /// Hit-tests the real, laid-out window at the points a user aims at, and
    /// reports each row's geometry so a zero-sized control is visible in the log
    /// instead of failing silently.
    ///
    /// `NSView.hitTest` returns `nil` for a view that is not in an ordered
    /// window, so a test that skips ordering would "pass" on any panel.
    func hitTestReport() -> (recorderSwallows: Bool, setButton: NSView?, modePopup: NSView?, lines: [String]) {
        window.orderFront(nil)
        guard let content = window.contentView else { return (false, nil, nil, []) }
        // Auto Layout inside an ordered-but-not-yet-displayed window defers a pass;
        // the subviews stay zero-sized and every aim point misses.
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        rows.values.forEach { $0.layoutSubtreeIfNeeded() }
        content.layoutSubtreeIfNeeded()
        let center = NSPoint(x: content.bounds.midX, y: content.bounds.midY)

        func aim(_ view: NSView) -> NSView? {
            let box = view.convert(view.bounds, to: content)
            return content.hitTest(NSPoint(x: box.midX, y: box.midY))
        }
        let swallows = content.hitTest(center) === recorder
        // Every row, not just the first: AppKit deactivates constraints that touch a
        // hidden view, and the panic row's mode popup is hidden by design, so its
        // button can end up with no positioning constraint at all.
        var lines: [String] = ["content=\(content.bounds)"]
        for (id, row) in rows {
            let b = row.button.convert(row.button.bounds, to: content)
            let m = row.mode.convert(row.mode.bounds, to: content)
            lines.append("\(id.title): button=\(b) mode=\(m) modeHidden=\(row.mode.isHidden) tas=\(row.button.translatesAutoresizingMaskIntoConstraints) cons=\(row.button.constraints.count) consMode=\(row.mode.constraints.count)")
        }
        // The first row that actually shows a mode popup, so the check measures a
        // real popup rather than the panic row's deliberately hidden one.
        let popupRow = rows.values.first { !$0.mode.isHidden } ?? rows[BindingID.all.first ?? .panic]
        return (swallows, popupRow.map { aim($0.button) } ?? nil, popupRow.map { aim($0.mode) } ?? nil, lines)
    }
}