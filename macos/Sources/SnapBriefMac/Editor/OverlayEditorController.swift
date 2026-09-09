// Port of `OverlayEditorWindow` (window lifecycle half: `CaptureNewAsync`, `OnSourceInitialized`,
// `OnLoaded`), SPEC §1.2, §6.2, §9.5, §9.8. Public contract: CONTRACTS.md "Editor".
import AppKit
import SnapBriefCore

protocol OverlayEditorDelegate: AnyObject {
    /// The capture is already saved to disk via `SessionAssetStore` (SPEC §1.2 step 8).
    func overlayEditor(_ editor: OverlayEditorController, didCommit capture: CaptureItem, annotations: [AnnotationItem])
    func overlayEditorDidCancel(_ editor: OverlayEditorController)
    /// Repeated global hotkey while a capture is present (SPEC §1.2 point 2).
    func overlayEditorRequestsNextCapture(_ editor: OverlayEditorController)
    /// SPEC §1.15 notification hook for a successful Cmd+S save.
    func overlayEditor(_ editor: OverlayEditorController, didSaveFileAt url: URL)
}

/// One screen's window + its always-present chrome (SPEC §9.5: "одно окно на каждый NSScreen").
struct OverlayScreenSlot {
    let window: OverlayWindow
    let contentView: OverlayContentView
    let screen: NSScreen
    /// This screen's `NSScreen.frame`, expressed in `ScreenGeometry`'s flipped global point space
    /// (top-left origin, Y down) — SPEC §9.5.
    let globalFlippedFrame: CGRect
}

/// Owns one full capture-and-annotate cycle (SPEC §1.2-§1.13). A new instance is created per
/// capture by the shell (`AppCoordinator`, out of this zone); `present()` shows the overlay
/// windows, and exactly one of the `OverlayEditorDelegate` completion methods fires before the
/// controller is torn down.
@MainActor
final class OverlayEditorController {
    weak var delegate: OverlayEditorDelegate?

    let workspaceContext: EditorWorkspaceContext
    let settings: HotkeySettings
    var language: String

    var desktopFrame: DesktopFrame
    private(set) var isPresented = false

    var slots: [OverlayScreenSlot] = []

    // Selection-mode state (SPEC §1.2 steps 7-9)
    var selectionScreenIndex: Int?
    var selectionStartLocal: CGPoint?
    var selectionRectLocal: CGRect = .zero

    // Editing-mode state (SPEC §1.3-§1.8)
    var capture: EditorCapture?
    var isNewCapture = true
    var cropRectLocal: CGRect = .zero
    var activeScreenIndex: Int?
    var captureIndex: Int
    var settingUp = false
    var busyCrop = false
    /// True only while the Cmd+S `NSSavePanel` is on screen (SPEC §1.13 point 1's "холст держит
    /// мышь"/crop/corner-drag guards are `busyCrop`/`captureResizeCorner`; a modal file dialog is
    /// a distinct kind of "busy" — finding 27 — kept separate so `busyCrop`'s meaning stays
    /// "a crop or resize PNG write is in flight").
    var isModalOpen = false

    let history = EditorHistory()
    var lastSnapshot: OverlaySnapshot?
    var visibleChipIds: Set<SBGuid> = []
    /// The single derived-source relative path written so far for the capture being edited
    /// (SPEC §1.8 point 3). `DefaultSessionAssetStore.saveOriginalPNG` writes to a path keyed
    /// only by `(sessionId, captureId)`, and `captureId` never changes across crop/resize
    /// operations within one edit (`CaptureCropper.crop` preserves the source capture's `id`), so
    /// every crop/resize simply *overwrites* the same file — there is no accumulation of
    /// temporary sources to sweep up on commit/cancel the way the Windows port needs
    /// `DeleteCreatedSourcesExcept` for. This field exists only so `close()`/`cancel()` for a
    /// *brand-new, never-committed* capture can delete that one file.
    var currentSourcePath: String?
    /// R1 fix: set once `persistCurrentSource` has backed up a *reopened* capture's pre-edit PNG
    /// (see `OverlayEditorController+Commit.swift`'s `backUpOriginalSourceIfNeeded`/
    /// `restoreOriginalSourceBackup`/`deleteOriginalSourceBackupIfNeeded`). Always `false` for a
    /// brand-new capture, which has its own delete-on-cancel path instead.
    var hasBackedUpOriginalSource = false

    // MARK: - Appearance (SPEC §1.3, §6.2 "Дополнение 2026-09-09")
    var activeColor: NSColor = EditorTheme.annotationPalette[0]
    var activeThickness: Double = 4
    /// True while `syncAppearance()` is writing into the popover's own controls, so their change
    /// callbacks (`onThicknessChanged`) don't re-enter `applyAppearance` (port of
    /// `_syncingAppearance`, `OverlayEditorWindow.Appearance.cs:13`).
    var syncingAppearance = false
    /// Non-nil exactly while a color/thickness edit session is open (the popover is showing, or a
    /// `smokeSetAppearance` probe is mid-session) — the snapshot to restore on undo if anything
    /// actually changes (port of `_appearanceBefore`).
    var appearanceBefore: OverlaySnapshot?
    /// True once at least one color/thickness edit in the current session actually changed the
    /// selected annotation (port of `_appearanceChanged`).
    var appearanceChanged = false
    var appearancePopover: NSPopover?
    var appearancePopoverController: EditorAppearancePopoverViewController?
    var appearancePopoverDelegate: AppearancePopoverDelegateProxy?

    // Corner-resize state (SPEC §1.6)
    var captureResizeCorner = -1
    var resizeSourceImage: CGImage?
    var resizeSourceRectLocal: CGRect = .zero
    var resizeOriginalCropRectLocal: CGRect = .zero

    // Editing-mode views (only non-nil while `activeScreenIndex` is set)
    var canvasContainerView: NSView?
    var canvasView: AnnotationCanvasView?
    var toolbarView: EditorToolbarView?
    var captureHandleViews: [CaptureHandleView] = []
    var resizeOutlineView: ResizeOutlineView?
    var chipViews: [SBGuid: CommentChipView] = [:]
    var shotNoteChipView: ShotNoteChipView?
    var contextNoteButtonView: ContextNoteButtonView?

    /// SPEC §1.2 step 5 / §9.8: the frontmost app before this overlay activates itself, restored
    /// by `close()` (finding 3 — an `.accessory` app's window never becomes key without an
    /// explicit `NSApp.activate`, and that activation must not permanently steal focus from
    /// whatever the user was in).
    private var previousFrontmostApplication: NSRunningApplication?
    /// R8 fix: when set (by the shell, before `present()`), `activateAndShowWindows()` uses this
    /// instead of reading `NSWorkspace.shared.frontmostApplication` itself. A "+ Снимок" chain's
    /// later controllers read that value only *after* the previous controller's own `close()`
    /// already reactivated it (asynchronously) and after this app's own `NSApp.activate` — a race
    /// that can report SnapBrief itself as frontmost instead of the app the whole chain started
    /// from. The shell (`AppCoordinator`) captures the value once, at the start of the chain, and
    /// passes it to every controller in that chain.
    var previousFrontmostApplicationOverride: NSRunningApplication?

    init(frame: DesktopFrame, workspace: EditorWorkspaceContext, settings: HotkeySettings, language: String) {
        desktopFrame = frame
        workspaceContext = workspace
        self.settings = settings
        self.language = language
        captureIndex = workspace.nextCaptureIndex
    }

    // MARK: - Presentation (SPEC §1.2 step 5, §6.2 layer 1)

    func present() {
        guard !isPresented else { return }
        isPresented = true
        createOverlayWindows()
        activateAndShowWindows()
        if let first = slots.first {
            first.window.makeKeyAndOrderFront(nil)
            first.window.makeFirstResponder(first.contentView)
        }
        restoreLastRegionIfNeeded()
    }

    /// SPEC §1.9 point 2: reopen a capture already saved to the stack. `desktopFrame` (passed to
    /// `init`) is a **fresh** screenshot (so the background layer behind the shade matches the
    /// current desktop and a corner-drag can still reveal newly-visible screen area is *not*
    /// possible per §1.6 — expansion for a reopened capture only ever draws from `image`, wired
    /// through `updateCaptureHandles`'s `isNewCapture == false` branch); `image` is the capture's
    /// own saved pixels, shown centered and scaled down to fit the screen.
    func presentExisting(capture: CaptureItem, image: CGImage) {
        guard !isPresented else { return }
        isPresented = true
        createOverlayWindows()
        activateAndShowWindows()

        guard let screenIndex = slots.firstIndex(where: { $0.screen == NSScreen.main }) ?? slots.indices.first else {
            close()
            return
        }
        slots[screenIndex].window.makeKeyAndOrderFront(nil)
        slots[screenIndex].window.makeFirstResponder(slots[screenIndex].contentView)

        activeScreenIndex = screenIndex
        isNewCapture = false
        captureResizeCorner = -1
        resizeSourceImage = nil

        let editorCapture = EditorCapture.fromCore(capture, image: image)
        editorCapture.displayLabel = (try? CaptureLabels.forIndex(captureIndex)) ?? "A"
        self.capture = editorCapture
        currentSourcePath = capture.sourceImagePath

        let contentSize = slots[screenIndex].contentView.bounds.size
        cropRectLocal = EditorGeometry.reopenCropRect(
            imageSize: CGSize(width: image.width, height: image.height), windowSize: contentSize)

        slots[screenIndex].contentView.hintView.isHidden = true
        slots[screenIndex].contentView.holeRectLocal = cropRectLocal

        setupEditor()
    }

    /// Shared window-construction half of `present()`/`presentExisting()` (SPEC §9.5: one
    /// `OverlayWindow` per `NSScreen`).
    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let window = OverlayWindow(screenFrame: screen.frame)
            let contentView = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = contentView

            let topLeftAppKit = CGPoint(x: screen.frame.minX, y: screen.frame.maxY)
            let globalOrigin = ScreenGeometry.flipToTopLeft(topLeftAppKit)
            let globalFlippedFrame = CGRect(origin: globalOrigin, size: screen.frame.size)

            let slot = OverlayScreenSlot(window: window, contentView: contentView, screen: screen, globalFlippedFrame: globalFlippedFrame)
            slots.append(slot)
            // Distinct per-screen title, used only for accessibility and to name CI screenshot
            // files (`DemoSessionFactory`/CONTRACTS.md "Shell" `--demo-screenshot`); SPEC has no
            // opinion on this window's title.
            window.title = "SnapBrief — Оверлей \(slots.count)"
            contentView.screenIndex = slots.count - 1
            contentView.desktopImage = screenSlice(for: slot)
            contentView.hintView.text = EditorStrings.selectHint(language)

            wireSelectionCallbacks(contentView, screenIndex: slots.count - 1)
            wireKeyEquivalents(window)
        }
    }

    /// Finding 3: an `.accessory`-policy app's borderless windows never become key purely from
    /// `makeKeyAndOrderFront` — the app itself has to be activated first. Remembers the previously
    /// frontmost app so `close()` can hand focus back.
    private func activateAndShowWindows() {
        previousFrontmostApplication = previousFrontmostApplicationOverride ?? NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        for slot in slots {
            slot.window.orderFrontRegardless()
        }
    }

    /// Crops this screen's slice of the composited desktop bitmap (SPEC §9.5).
    private func screenSlice(for slot: OverlayScreenSlot) -> CGImage? {
        let topLeft = ScreenGeometry.framePixels(fromScreenPoint: CGPoint(x: slot.screen.frame.minX, y: slot.screen.frame.maxY), frame: desktopFrame)
        let bottomRight = ScreenGeometry.framePixels(fromScreenPoint: CGPoint(x: slot.screen.frame.maxX, y: slot.screen.frame.minY), frame: desktopFrame)
        let rect = CGRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
        return desktopFrame.image.cropping(to: rect)
    }

    // MARK: - Repeated hotkey (SPEC §1.2 point 2)

    func handleGlobalHotkey() {
        guard isPresented else { return }
        guard capture != nil, !busyCrop, !isModalOpen, captureResizeCorner < 0, canvasView?.manipulating != true else { return }
        commit(addNext: true)
    }

    func close() {
        guard isPresented else { return }
        isPresented = false
        for slot in slots {
            slot.window.orderOut(nil)
        }
        slots.removeAll()
        // Finding 3: hand focus back to whatever app was frontmost before this overlay activated
        // itself (`activateAndShowWindows()`), matching the Windows port's plain non-activating
        // `ShowStackWithoutActivation` behavior for everything downstream of the overlay closing.
        previousFrontmostApplication?.activate(options: [])
        previousFrontmostApplication = nil
    }

    // MARK: - Helpers shared by the extensions in this zone

    func slotIndex(for screen: NSScreen) -> Int? {
        slots.firstIndex(where: { $0.screen == screen })
    }

    /// Converts a point in `slots[screenIndex]`'s local space to the shared global flipped point
    /// space (SPEC §9.5), and back.
    func globalPoint(fromLocal point: CGPoint, screenIndex: Int) -> CGPoint {
        let origin = slots[screenIndex].globalFlippedFrame.origin
        return CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }

    func localPoint(fromGlobal point: CGPoint, screenIndex: Int) -> CGPoint {
        let origin = slots[screenIndex].globalFlippedFrame.origin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}
