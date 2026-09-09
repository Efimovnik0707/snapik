// Port of `OverlayEditorWindow.xaml` window chrome + `CaptureOverlay.xaml`, SPEC §1.2 step 5,
// §6.2, §9.8. CONTRACTS.md "Editor": one `OverlayWindow` per `NSScreen`.
import AppKit

/// Full-screen, borderless, opaque overlay window for one `NSScreen` (SPEC §9.5/§9.8: macOS
/// cannot host one borderless window spanning multiple displays the way the Windows virtual-
/// desktop rect does, so `OverlayEditorController` creates one of these per screen, each showing
/// its own slice of the frozen `DesktopFrame.image`).
///
/// - `.borderless`, opaque, background `#0A0D12` (SPEC §1.2 step 5: "Отказ от per-pixel
///   transparency — осознанное решение по производительности", repeated here on macOS).
/// - `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
///   (SPEC §9.8: "Оверлей поверх всего").
/// - `sharingType = .none` so the overlay itself never appears in a *different* app's screen
///   capture (SPEC §9.8 "Исключение из чужих захватов" — the analogous concern in the other
///   direction from "hide our own windows before taking the frame", which is `Capture`'s job).
/// - Overrides `canBecomeKey`/`canBecomeMain` to `true`: unlike the non-activating stack panel
///   (SPEC §9.8, `EdgeStackWindow`), the overlay must accept keyboard focus for text-field editing
///   inside comment chips and for `keyDown` tool/undo/redo/Escape handling (SPEC §7.5).
final class OverlayWindow: NSWindow {
    /// Set by `OverlayEditorController+Keys.wireKeyEquivalents`. Returning `true` consumes the
    /// event; `false` falls through to normal `performKeyEquivalent`/`keyDown` delivery.
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = EditorTheme.overlayWindowBackground
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        hasShadow = false
        sharingType = .none
        acceptsMouseMovedEvents = true
        setFrame(screenFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onKeyEquivalent, onKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
