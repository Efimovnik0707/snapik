// Port of `src/Snapik.App/Controls/HotkeyField.xaml(.cs)`, SPEC §7.3, SPEC-DELTA-3 §1.5 G-6, G-7
// and §1.6 O-4.
import AppKit
import SnapikCore

/// One hotkey as a row of key capsules with a hint beside them. Clicking it (or tabbing into it)
/// starts recording, and the first non-modifier key held together with Cmd, Option, Shift or Control
/// writes a new hotkey id in the same `"custom:{modifiers}:{virtualKey}"` format the settings file
/// has always used. A key pressed alone is not a shortcut: it would be registered globally and taken
/// away from every other application.
///
/// A refusal leaves the recording running and the old shortcut where it was: the user presses another
/// combination and the field goes on from there.
///
/// Deviation: on macOS a bare modifier press is delivered as `flagsChanged`, not `keyDown`, so
/// recording a lone modifier as the whole shortcut (which Windows supports) is not implemented here
/// — a Carbon-registered global hotkey has no representation for it (SPEC §7.6, Q7).
final class HotkeyRecorderField: NSView {
    /// The capsules of a shortcut, in the order this platform reads them: `⌃ ⌥ ⇧ ⌘` and the key.
    /// The id is the Windows one (bit 1 = Option, bit 2 = Command, bit 8 = Control), the symbols are
    /// the Mac ones (SPEC-DELTA-3 §4).
    static func labelParts(forId id: String) -> [String] {
        let identifier = HotkeyIdentifier.parse(id)
        var parts: [String] = []
        if identifier.modifiers.contains(.windows) { parts.append("⌃") }
        if identifier.modifiers.contains(.alt) { parts.append("⌥") }
        if identifier.modifiers.contains(.shift) { parts.append("⇧") }
        if identifier.modifiers.contains(.control) { parts.append("⌘") }
        if identifier.windowsVirtualKey == 0x13 {
            parts.append("Pause")
        } else if identifier.windowsVirtualKey == 0x2C {
            parts.append("Print Screen")
        } else if let name = KeyCodeMapping.name(forWindowsVK: identifier.windowsVirtualKey) {
            parts.append(name.uppercased())
        } else {
            parts.append(String(format: "0x%02X", identifier.windowsVirtualKey))
        }
        return parts
    }

    private static let idleCaption = "Нажми, чтобы изменить"
    private static let recordingCaption = "Нажмите своё сочетание клавиш"
    private static let needsModifierCaption = "Добавь Cmd, Option или Shift"
    private static let reservedCaption = "Это сочетание занято системой"
    private static let takenCaption = "Уже занято"
    private static let unassignedCaption = "Не назначено"

    private let capsules = NSView()
    private let caption = NSTextField(labelWithString: "")
    private var capsuleViews: [NSView] = []

    private(set) var isRecording = false
    // The caption a refusal left there, and whether the frame goes red with it: a missing modifier is
    // an instruction, a combination the system keeps or a neighbour holds is a refusal.
    private var notice: String?
    private var refused = false

    /// Raised after the user records a new shortcut, never for a value set in code.
    var onHotkeyChanged: ((HotkeyRecorderField) -> Void)?
    /// Recording is about to consume every keystroke (Return included, SPEC §7.3): the owner uses
    /// this to stop the default button of its window from also reacting to Return.
    var onBeginRecording: ((HotkeyRecorderField) -> Void)?
    var onFinishRecording: ((HotkeyRecorderField) -> Void)?

    /// The other fields of the same window. A field does not know its neighbours by itself: the
    /// window ties them together, and a combination one of them already holds is refused here, while
    /// it is being pressed, instead of failing at the registration with a message about another
    /// application.
    var conflictsWith: [HotkeyRecorderField] = []

    /// Shortcuts held elsewhere, read when they are needed rather than copied: the wizard has one
    /// field and the settings behind it, and the combination standing on "save the whole screen"
    /// must not be recordable on the capture shortcut either.
    var reservedIds: [() -> String] = []

    var language = "ru" { didSet { refresh() } }

    var currentId: String = HotkeyIdentifier.fallback.id { didSet { refresh() } }

    /// Whether the shortcut is switched on at all. A shortcut that is off has no combination to show:
    /// the id behind it is still the one the file carries, and showing it would offer a shortcut that
    /// does nothing. The field says "Не назначено" instead.
    var isAssigned = true { didSet { refresh() } }

    var palette: ThemePalette = ThemeService.palette(nil) { didSet { refresh() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
        caption.font = NSFont.systemFont(ofSize: 12)
        addSubview(capsules)
        addSubview(caption)
        toolTip = "Нажмите своё сочетание клавиш"
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { beginRecording() }
        return result
    }

    override func resignFirstResponder() -> Bool {
        // Focus can leave the field without a key ever arriving; the capsules must come back then.
        isRecording = false
        clearNotice()
        refresh()
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func layout() {
        super.layout()
        let capsuleHeight: CGFloat = 22
        capsules.frame = NSRect(
            x: 10, y: bounds.height - 8 - capsuleHeight, width: max(0, bounds.width - 20),
            height: capsuleHeight)
        caption.frame = NSRect(x: 10, y: 6, width: max(0, bounds.width - 20), height: 16)
        var x: CGFloat = 0
        for view in capsuleViews {
            view.frame = NSRect(x: x, y: 0, width: view.frame.width, height: capsuleHeight)
            x += view.frame.width + 5
        }
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        clearNotice()
        refresh()
        onBeginRecording?(self)
    }

    private func endRecording() {
        isRecording = false
        refresh()
        onFinishRecording?(self)
    }

    private func clearNotice() {
        notice = nil
        refused = false
    }

    /// What the save block calls on both fields when one combination stands for two actions: the
    /// shortcut was recorded before the neighbour took it, so the refusal comes at saving time.
    func showConflict() {
        _ = refuse(Self.takenCaption, red: true)
    }

    /// Whether the field is standing on a refusal, with the red frame that goes with it.
    var showsConflict: Bool { refused }

    @discardableResult
    private func refuse(_ text: String, red: Bool) -> Bool {
        notice = text
        refused = red
        refresh()
        return false
    }

    // MARK: - Recording

    /// Port of `OnCaptureKeyDown`: every key down while recording is consumed (Return included, SPEC
    /// §7.3), and — since macOS never delivers a bare modifier through `keyDown` — it always stands
    /// for a real key.
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        // Tab keeps walking the window instead of becoming a hotkey, and Escape leaves the recording
        // with the shortcut the field already had.
        if event.keyCode == 48 {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            clearNotice()
            endRecording()
            return
        }
        _ = recordKey(macKeyCode: Int(event.keyCode), flags: event.modifierFlags)
    }

    override func keyUp(with event: NSEvent) {
        if isRecording { return }
        super.keyUp(with: event)
    }

    /// Port of `RecordKey`. The modifier bits follow the fixed mapping of `GlobalHotkeyService`
    /// (Alt = Option, Control = Command, Shift = Shift, Windows = Control). `true` means the shortcut
    /// was taken.
    @discardableResult
    func recordKey(macKeyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
        var modifiers: HotkeyModifiers = []
        if flags.contains(.option) { modifiers.insert(.alt) }
        if flags.contains(.command) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.windows) }
        return recordKey(macKeyCode: macKeyCode, modifiers: modifiers)
    }

    /// The modifiers are an argument rather than a reading of the keyboard, so the smoke run can hold
    /// a combination the real keyboard is not holding.
    @discardableResult
    func recordKey(macKeyCode: Int, modifiers: HotkeyModifiers) -> Bool {
        guard isRecording else { return false }
        guard let virtualKey = KeyCodeMapping.windowsVK(forMacKeyCode: macKeyCode),
            virtualKey > 0, virtualKey < 255
        else { return false }
        // A modifier is what the shortcut is held together with, never what it ends with, whichever
        // way the key arrived here.
        if HotkeyRules.isModifierKey(virtualKey) { return false }
        // Nothing is recorded and the recording goes on: the field asks for a modifier instead of
        // taking a key that would then belong to Snapik everywhere on the machine.
        if modifiers.rawValue == 0 && !HotkeyRules.isShortcutOnItsOwn(virtualKey) {
            return refuse(Self.needsModifierCaption, red: false)
        }
        // A combination the system answers before any application does would be a shortcut that never
        // fires, and one a neighbouring field holds would take the other action away.
        if HotkeyRules.isSystemReserved(modifiers: modifiers, virtualKey: virtualKey) {
            return refuse(Self.reservedCaption, red: true)
        }
        let id = "custom:\(modifiers.rawValue & 0xF):\(virtualKey)"
        if isTaken(id) { return refuse(Self.takenCaption, red: true) }

        clearNotice()
        currentId = id
        isRecording = false
        refresh()
        onHotkeyChanged?(self)
        onFinishRecording?(self)
        return true
    }

    // A combination another field of the window (or of the settings behind it) already holds. The
    // comparison is by gesture, not by text: `"print-screen"` and `"custom:0:44"` are one shortcut.
    private func isTaken(_ id: String) -> Bool {
        if conflictsWith.contains(where: {
            $0 !== self && $0.isAssigned && HotkeyRules.sameGesture($0.currentId, id)
        }) {
            return true
        }
        return reservedIds.contains { HotkeyRules.sameGesture($0(), id) }
    }

    // MARK: - Drawing

    private func refresh() {
        for view in capsuleViews { view.removeFromSuperview() }
        capsuleViews = []
        layer?.backgroundColor = palette.elevated.cgColor

        if !isRecording {
            if isAssigned {
                for part in Self.labelParts(forId: currentId) { capsuleViews.append(makeCapsule(part)) }
            } else {
                // A shortcut that is switched off shows no capsules: the id behind it would otherwise
                // be read out of the file and look like a working combination.
                capsuleViews.append(makeUnassignedLabel())
            }
        }
        for view in capsuleViews { capsules.addSubview(view) }

        // The recording frame is the accent of the current theme, so it follows the accent the user
        // picks; the idle frame is the line of the palette.
        if refused {
            layer?.borderColor = palette.danger.cgColor
        } else if isRecording {
            layer?.borderColor = ThemeService.accent(ThemeService.currentAccent).focus.cgColor
        } else {
            layer?.borderColor = palette.elevatedLine.cgColor
        }
        caption.textColor = refused ? palette.danger : palette.textMuted
        caption.stringValue = MacUiText.text(
            notice ?? (isRecording ? Self.recordingCaption : Self.idleCaption), language: language)
        needsLayout = true
    }

    /// Smoke: what the field is saying under the capsules — the instruction of a missing modifier,
    /// the refusal of a combination the system keeps, or the idle line.
    var smokeCaption: String { caption.stringValue }

    private func makeCapsule(_ key: String) -> NSView {
        let label = NSTextField(labelWithString: key)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = palette.text
        label.sizeToFit()
        let capsule = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 14, height: 22))
        capsule.wantsLayer = true
        capsule.layer?.backgroundColor = palette.hover.cgColor
        capsule.layer?.borderColor = palette.elevatedLine.cgColor
        capsule.layer?.borderWidth = 1
        capsule.layer?.cornerRadius = 5
        label.frame = NSRect(
            x: 7, y: (22 - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        capsule.addSubview(label)
        return capsule
    }

    private func makeUnassignedLabel() -> NSView {
        let label = NSTextField(labelWithString: MacUiText.text(Self.unassignedCaption, language: language))
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = palette.textMuted
        label.sizeToFit()
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width, height: 22))
        label.frame = NSRect(
            x: 0, y: (22 - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        holder.addSubview(label)
        return holder
    }
}
