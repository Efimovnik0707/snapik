// Port of the hotkey recording field (`HotkeySettingsWindow.xaml.cs:108-145`), SPEC §7.3.
import AppKit
import SnapikCore

protocol HotkeyRecorderFieldDelegate: AnyObject {
    func hotkeyRecorderField(_ field: HotkeyRecorderField, didRecord id: String)
    /// Finding 8: recording is about to start consuming every keystroke (Enter included, SPEC
    /// §7.3) — the delegate uses this to stop the window's default button from also reacting to
    /// Enter while the field is armed.
    func hotkeyRecorderFieldDidBeginRecording(_ field: HotkeyRecorderField)
    func hotkeyRecorderFieldDidFinishRecording(_ field: HotkeyRecorderField)
}

/// Read-only field: focus or a click begins recording (shows "Нажмите клавишу…"); the next
/// non-modifier key press is recorded as a `"custom:{mods}:{vk}"` id and focus moves on to the
/// Save button (SPEC §7.3: "режим записи завершается, и фокус переходит на кнопку «Сохранить»").
///
/// Deviation: on macOS, a bare modifier key press/release is delivered as `flagsChanged`, not
/// `keyDown`/`keyUp` — recording a *lone* modifier as the whole hotkey (which Windows supports,
/// §7.3) is intentionally not implemented here, since a Carbon-registered global hotkey has no
/// representation for "no real key, just a modifier" (SPEC §7.6, Q7). The Hotkeys tab documents
/// this limitation in a caption instead (`SettingsTabViews.swift`).
final class HotkeyRecorderField: NSView {
    weak var delegate: HotkeyRecorderFieldDelegate?

    private(set) var isRecording = false
    private let label = NSTextField(labelWithString: "")
    private var focusRingLayer: CALayer?

    var language: String = "ru" { didSet { updateIdleLabel() } }
    var currentId: String = HotkeyIdentifier.fallback.id { didSet { updateIdleLabel() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DarkPalette.settingsFieldBackground.cgColor
        layer?.borderColor = DarkPalette.fieldBorder.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6

        label.textColor = DarkPalette.primaryText
        label.font = NSFont.systemFont(ofSize: 13)
        addSubview(label)

        toolTip = "Нажмите своё сочетание клавиш"
        updateIdleLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 10, dy: 7)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { beginRecording() }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    private func beginRecording() {
        isRecording = true
        label.stringValue = MacUiText.text("Нажмите клавишу…", language: language)
        layer?.borderColor = DarkPalette.focusRing.cgColor
        delegate?.hotkeyRecorderFieldDidBeginRecording(self)
    }

    private func stopRecording() {
        isRecording = false
        layer?.borderColor = DarkPalette.fieldBorder.cgColor
        updateIdleLabel()
    }

    private func updateIdleLabel() {
        guard !isRecording else { return }
        label.stringValue = HotkeyIdentifier.parse(currentId).label
    }

    /// Port of `OnCaptureKeyDown` (`:124-130`): every key down while recording is consumed
    /// (Enter/Tab/Escape included, SPEC §7.3), and — since macOS never delivers a bare modifier
    /// through `keyDown` — always represents a real key, so it is recorded directly.
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        recordKey(macKeyCode: Int(event.keyCode), flags: event.modifierFlags)
    }

    override func keyUp(with event: NSEvent) {
        if isRecording { return }
        super.keyUp(with: event)
    }

    /// Port of `RecordKey` (`:131-145`). Modifier bits follow the fixed mapping documented in
    /// `GlobalHotkeyService` (Alt=Option, Control=Command, Shift=Shift, Windows=(Mac) Control).
    private func recordKey(macKeyCode: Int, flags: NSEvent.ModifierFlags) {
        var modifiers: HotkeyModifiers = [.noRepeat]
        if flags.contains(.option) { modifiers.insert(.alt) }
        if flags.contains(.command) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.windows) }

        guard let id = HotkeyIdentifier.makeCustomId(macKeyCode: macKeyCode, modifiers: modifiers) else { return }

        currentId = id
        stopRecording()
        delegate?.hotkeyRecorderField(self, didRecord: id)
        delegate?.hotkeyRecorderFieldDidFinishRecording(self)
    }
}
