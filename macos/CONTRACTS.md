# Контракты модулей macOS-порта Snapik

Все исполнители пишут против этих имён. Источник поведения: `SPEC.md` (читать обязательные разделы своей зоны целиком). Язык кода: Swift 5 language mode (компилятор 6.1 на CI, 6.3 на Windows), без strict concurrency, без actors, без `Sendable`-аннотаций; `@MainActor` только там, где компилятор требует. Без сторонних пакетов.

## Таргеты и зоны (папки не пересекаются)

| Таргет | Папка | Владелец |
|---|---|---|
| SnapikCore (Foundation only, компилируется на Windows) | `Sources/SnapikCore/{Models,Editing,Exporting,Persistence,Serialization,Localization,Settings}` | exec-core |
| SnapikCore | `Sources/SnapikCore/Transport/**`, `Tests/SnapikCoreTests/Transport/**` | exec-transport |
| SnapikCore | `Sources/SnapikCore/Geometry/ResizeGeometry.swift`, `Tests/SnapikCoreTests/Geometry/**` | exec-imaging |
| SnapikMac | `Sources/SnapikMac/Transport/**`, `Tests/SnapikMacTests/Transport/**` | exec-transport |
| SnapikMac | `Sources/SnapikMac/Imaging/**`, `Sources/SnapikMac/Capture/**`, `Tests/SnapikMacTests/Imaging/**` | exec-imaging |
| SnapikMac | `Sources/SnapikMac/Editor/**` | exec-editor |
| SnapikMac | `Sources/SnapikMac/App/**`, `Sources/SnapikMac/Stack/**`, `Sources/SnapikMac/Settings/**`, `Sources/SnapikMac/Hotkeys/**`, `Sources/SnapikMac/main.swift`, `Tests/SnapikMacTests/App/**` | exec-shell |

Публичный API Core описан в `CORE-API.md` (пишет exec-core). Если файла ещё нет, читать сами Swift-файлы в `Sources/SnapikCore`, а при их отсутствии брать имена из SPEC.md §2–§4: `SnapikSession`, `CaptureItem`, `AnnotationItem`, `AnnotationKind`, `SessionHistory`, `SessionOperations`, `CaptureCropper`, `CaptureLabels`, `PromptGenerator`, `ExportManifest`, `PreparedExport`, `ExportImageEntry`, `ExportImageContext`, `FileExportService`, `JsonSessionStore`, `SessionAssetStore`, `SessionStore` (протокол, бывший ISessionStore), `SnapikPaths`, `UiLanguage` (enum `.ru/.en`) и `UiStrings`, `AppSettings` (+ `HotkeyBinding`).

Внутри SnapikMac все папки один модуль, `internal` видимость достаточна. Между Core и Mac: `public`.

## Координаты (SPEC §9.5)

Слой преобразования живёт в `Sources/SnapikMac/Capture/ScreenGeometry.swift` (exec-imaging):

```swift
struct DesktopFrame {              // аналог Windows DesktopFrame
    let image: CGImage             // весь виртуальный рабочий стол в пикселях
    let left: Int                  // в перевёрнутой системе (Y вниз, начало = левый-верхний угол объединения экранов), пиксели
    let top: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat             // пикселей на точку в кадре (max backingScaleFactor)
}
enum ScreenGeometry {
    static var globalPointsRect: CGRect { get }                         // объединение NSScreen.frame (точки, Y вверх)
    static func flipToTopLeft(_ p: CGPoint) -> CGPoint                  // точки, Y вниз
    static func framePixels(fromScreenPoint p: CGPoint, frame: DesktopFrame) -> CGPoint
    static func screenPoint(fromFramePixels p: CGPoint, frame: DesktopFrame) -> CGPoint // обратное (Y вверх), для позиционирования окон
}
```

Решение Q4: кадр = все дисплеи, собранные в один битмап с масштабом `max(backingScaleFactor)`, дисплеи с меньшим масштабом апскейлятся. Оверлей: по одному `NSWindow` на каждый `NSScreen`, каждый показывает свой участок кадра.

## Захват (exec-imaging, `Sources/SnapikMac/Capture/`)

```swift
protocol ScreenCaptureServicing {
    var hasScreenRecordingPermission: Bool { get }
    func requestScreenRecordingPermission()                             // CGRequestScreenCaptureAccess
    func captureDesktop(includeCursor: Bool, completion: @escaping (Result<DesktopFrame, Error>) -> Void)
}
final class ScreenCaptureService: ScreenCaptureServicing  // ScreenCaptureKit (SCScreenshotManager), fallback CGDisplayCreateImage
enum CaptureCursorDrawing { static func draw(into ctx: CGContext, frame: DesktopFrame) }   // NSCursor.current + hotspot
```

## Imaging (exec-imaging, `Sources/SnapikMac/Imaging/`)

```swift
enum RegionBlur {   // SPEC §2.8, трёхпроходный box-blur, (sum + divisor/2)/divisor, побайтно как Windows
    static func blur(_ image: CGImage, region: CGRect /*пиксели*/, radius: Int) -> CGImage
}
enum ImageCodec {   // SPEC §1.13
    enum Format { case png; case jpeg(quality: Int) }   // quality 1...100
    static func encode(_ image: CGImage, format: Format) -> Data?
    static func decodePNG(_ data: Data) -> CGImage?
    static func loadImage(at url: URL) -> CGImage?
    static func writeAtomically(_ data: Data, to url: URL) throws   // временный файл + replace
}
final class ExportImageRenderer: ExportImageRendering { }   // SPEC §4.5: протокол из Core; шапка 48 px, метки, стрелки, blur, redaction
enum AnnotationPainter {    // общий рисовальщик отметок: экран (§4.6, §6.3) и экспорт (§4.5)
    static func draw(_ annotations: [AnnotationItem], imageSize: CGSize, in ctx: CGContext, options: AnnotationPaintOptions)
}
struct AnnotationPaintOptions { var showLabels: Bool; var labelFor: (AnnotationItem) -> String?; var sourceImage: CGImage? /* нужен для blur */ }
```
Экранный холст (exec-editor) вызывает `AnnotationPainter.draw` для отрисовки отметок и `RegionBlur.blur` для превью, чтобы рендер на экране и в экспорте совпадал.

## Transport (exec-transport)

Core-часть (`Sources/SnapikCore/Transport/`, кросс-платформенная, тестируется 36 тестами §8.3):
```swift
public struct ClipboardSnapshot { public let sequence: Int; public let hasText: Bool; public let text: String?; public let filePaths: [String]; public let hasImage: Bool }
public protocol ClipboardServicing: AnyObject {
    func capture(_ completion: @escaping (ClipboardSnapshot) -> Void)
    func setPackageGuarded(paths: [String], text: String, expectedSequence: Int?, completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void)
    func setPNGGuarded(path: String, expectedSequence: Int?, completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void)
    func setTextGuarded(text: String, expectedSequence: Int?, completion: @escaping (Result<ClipboardSnapshot, Error>) -> Void)
}
public struct ForegroundTarget { public let processName: String; public let bundleIdentifier: String?; public let windowTitle: String?; public let windowId: Int; public let focusedElementId: String? }
public protocol ForegroundTargetServicing: AnyObject { func currentTarget() -> ForegroundTarget? }
public protocol InputInjecting: AnyObject { func injectPaste(alternate: Bool, completion: @escaping (Bool) -> Void) /* Cmd+V или Option+V; Enter никогда */ }
public protocol PasteIntentObserving: AnyObject { var onPasteIntent: ((PasteIntent) -> Void)? { get set }; func start() throws; func stop(); var isRunning: Bool { get } }
public struct PasteIntent { public let alternate: Bool; public let timestamp: Date; public let synthetic: Bool }
public final class PasteCoordinator { ... }                    // SPEC §5.2 машина состояний целиком
public struct TargetProfile { ... }; public enum BuiltInTargetProfiles { ... }   // SPEC §5.3; на macOS матчить по bundleIdentifier ИЛИ localizedName (Q2)
public final class CodexDesktopPasteCompletionService { ... } // SPEC §5.4
public final class UnobservableAcceptanceObserver { ... }     // SPEC §5.7
public enum PasteIntentKeyState { ... }                        // правила распознавания §5.8
```
Mac-часть (`Sources/SnapikMac/Transport/`): `MacClipboardService: ClipboardServicing` (NSPasteboard: `public.file-url` для каждого файла + `public.utf8-plain-text` + для одного снимка ещё `public.png`/`public.tiff`; `changeCount` = sequence), `MacPasteIntentObserver: PasteIntentObserving` (CGEvent tap listen-only, `.cgSessionEventTap`, `keyDown`; без разрешения `start()` бросает `TransportError.permissionMissing`), `MacForegroundTargetService` (NSWorkspace.frontmostApplication + AX focused window/element при наличии Accessibility), `MacInputInjector` (CGEvent post Cmd+V / Option+V, помечает свои события `CGEventField.eventSourceUserData = 0x534E4150`, чтобы наблюдатель их игнорировал), `TransportPermissions` (`AXIsProcessTrusted`, `CGPreflightListenEventAccess`, `CGRequestListenEventAccess`).

Дефолтные bundle id профилей (Q2, подтвердить на реальной машине): Codex Desktop `com.openai.codex`, ChatGPT `com.openai.chat`, Claude Desktop `com.anthropic.claudefordesktop`, Terminal `com.apple.Terminal`, iTerm2 `com.googlecode.iterm2`, VS Code `com.microsoft.VSCode`, Cursor `com.todesktop.230313mzl4w4u92`. Хранить как константы с матчем и по `localizedName` (`Codex`, `ChatGPT`, `Claude`, `Code`, `Cursor`, `Terminal`, `iTerm2`).

## Editor (exec-editor, `Sources/SnapikMac/Editor/`)

```swift
protocol OverlayEditorDelegate: AnyObject {
    func overlayEditor(_ editor: OverlayEditorController, didCommit capture: CaptureItem, annotations: [AnnotationItem]) // снимок уже сохранён на диск через SessionAssetStore
    func overlayEditorDidCancel(_ editor: OverlayEditorController)
    func overlayEditorRequestsNextCapture(_ editor: OverlayEditorController)   // повторная горячая клавиша (§1.2 п.2)
    func overlayEditor(_ editor: OverlayEditorController, didSaveFileAt url: URL)   // для уведомления §1.15
}
final class OverlayEditorController {
    init(frame: DesktopFrame, workspace: EditorWorkspaceContext, settings: AppSettings, language: UiLanguage)
    weak var delegate: OverlayEditorDelegate?
    func present()                     // создаёт окна на всех экранах
    func handleGlobalHotkey()          // §1.2 п.2: коммит текущего и следующий захват, либо игнор если crop/resize/mouse
    func close()
    var isPresented: Bool { get }
}
struct EditorWorkspaceContext { let session: SnapikSession; let sessionDirectory: URL; let assetStore: SessionAssetStore; let nextCaptureIndex: Int }
```
Внутри: `OverlayWindow` (NSWindow, `.borderless`, level `.screenSaver`, `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary]`), `AnnotationCanvasView` (NSView), `EditorToolbarView`, `CommentChipView`, `SelectionHandles`, `EditorHistory` (обёртка над Core `SessionHistory`), `EditorState`. Сохранение файла: `NSSavePanel` + `ImageCodec` + `AnnotationPainter`.

## Shell (exec-shell)

`AppDelegate` (`Sources/SnapikMac/App/`), `AppCoordinator` (цикл захвата §1.2 п.3, ротация сессий §1.11–1.12, владеет `SessionWorkspace`, `PasteCoordinator`, `MacClipboardService`, `ScreenCaptureService`, `OverlayEditorController`), `StatusBarController` (NSStatusItem + меню §1.1), `EdgeStackWindowController` (NSPanel §1.9, §6.4), `HotkeySettingsWindowController` (§6.5, §7.3), `GlobalHotkeyService` (Carbon, §7.6), `HotkeyRecorderField` (§7.3), `LaunchAtLoginService` (SMAppService, §9.4), `SingleInstanceCoordinator` (§9.6), `NotificationService` (UNUserNotificationCenter, §1.15), `CommandLineOptions` (§1.19), `SmokeTestRunner` (§8.4, флаг `--smoke-test`, выход кодом 0/1, печать отчёта в stdout), `DemoSessionFactory` (`--demo`; дополнительно флаг `--demo-screenshot <dir>`: после показа стопки и оверлея сохранить снимки своих окон через `CGWindowListCreateImage` в этот каталог и через 3 с завершиться; нужно для CI).

## Решения по открытым вопросам SPEC §10

- Q1: быстрое сохранение экрана = `Shift+Cmd+Option+S`, выключено по умолчанию.
- Q2: см. bundle id выше, плюс матч по имени.
- Q3: не проверяемо без Mac; в README статус «не подтверждено».
- Q4: общий кадр всех дисплеев в максимальном масштабе (см. выше).
- Q5: без sandbox, прямое распространение DMG, ad-hoc подпись.
- Q6: диагностические строки 1:1 (русские), как на Windows.
- Q7: Carbon для сочетаний; одиночный модификатор не поддерживается, в настройках показывать текст об ограничении.

## Общие правила

- Строки UI только через `UiStrings` (Core), дословно из SPEC §1.20. Кириллица: первый тест-кейс.
- Логи: `os.Logger(subsystem: "live.yesworkflow.snapik", category: ...)` плюс файл `startup.log` в каталоге данных (§1.19).
- Никаких `fatalError`/`try!` в рабочих путях; ошибки в статус стопки текстом из спеки.
- Каждый файл начинается с комментария `// Port of <windows file>, SPEC §x.y`.
- Компилятора AppKit локально нет: писать консервативно, проверять сигнатуры API дважды, избегать редких API. Предпочитать `NSView` с ручным `draw(_:)` вместо layer-трюков.

## Дополнение sync 2 (2026-09-09): новые кросс-зонные сигнатуры

Спека дельты: `SPEC-DELTA-2.md`, `SPEC-DELTA-2A.md` (транспорт), `SPEC-DELTA-2B.md` (UI). Владение папками на sync 2: см. таблицу «Разбиение» в `SPEC-DELTA-2B.md`.

```swift
// Core (core-shell)
public enum AnnotationKind { …; case comment }                       // JSON "comment"
public struct AnnotationItem { public var parentAnnotationId: SBGuid?; public var arrowStyle: String /* "straight" */ }
public struct HotkeySettings { public var autoSaveCaptures: Bool /* false */; public var playSounds: Bool /* true */ }
public enum CaptureLabels { public static func forIndex(_ index: Int) throws -> String }   // A..Z, AA, ..., ошибка только при index < 0

// Core Transport (transport)
public enum PasteIntentGesture { case commandV, optionV, controlV }
public struct PasteIntent { …; public let gesture: PasteIntentGesture; public var alternate: Bool { gesture != .commandV }; public let intercepted: Bool }
public protocol InputInjecting { func injectPaste(gesture: PasteIntentGesture, completion: @escaping (Bool) -> Void); func injectPaste(alternate: Bool, completion: @escaping (Bool) -> Void) /* обёртка */ }
public final class PasteIntentInterceptionState { func shouldSuppress(isVKey: Bool, isKeyDown: Bool, isInjected: Bool, interceptThisGesture: Bool) -> Bool; func reset() }
extension CodexDesktopPasteCompletionService { public func completeSequential(intent:ownedPackageReceipt:immutableImagePaths:immutablePromptText:cancellationToken:completion:) }
public enum ClipboardEchoDetector { public static func isReceiverEcho(_ snapshot: ClipboardSnapshot, promptText: String) -> Bool }
extension ClipboardSnapshot { public var hasFiles: Bool }
extension CodexPasteCompletionResult { public var currentClipboardReceipt: ClipboardSnapshot? }

// Mac Transport (transport)
final class MacPasteIntentObserver { init(foreground:clipboardSequence:shouldIntercept: ((PasteIntent) -> Bool)?); var onDiagnostic: ((String) -> Void)?; private(set) var tapMode: PasteIntentTapMode? }
final class MacClipboardService { init(queue: DispatchQueue = .main, pngItemIncludesFileURL: Bool = true); func diagnosticTypes() -> [String] }

// App (transport владеет этими файлами): AppCoordinator+PasteIntent.swift, PasteInterceptPredicate.swift, AsyncGate.swift
final class AsyncGate { var isBusy: Bool; func wait() async; func release() }
extension AppCoordinator {   // поля добавляет transport в AppCoordinator.swift
    var pasteObservedForCurrentPackage: Bool; var pasteIntentTransition: Task<Void, Never>?
    let clipboardPublicationGate: AsyncGate; var receiverEchoWatchTask: Task<Void, Never>?
    func handlePasteIntent(_ intent: PasteIntent); func republishPackageForReuse(paths: [String], prompt: String) async
    func startReceiverEchoWatch(paths: [String], prompt: String); func cancelReceiverEchoWatch()
}

// Shell → Stack
struct StackCaptureRow { let id: SBGuid; let label: String; let thumbnail: NSImage?; let noteCount: Int }
extension EdgeStackWindowController { func setSelectedCapture(_ id: SBGuid?) }
// Shell (core-shell), вызывается из Stack/ и App/
enum CaptureFeedbackSound { static func capture(enabled: Bool); static func tick(enabled: Bool); static func verifyWaveHeaders() throws }
enum AutoSaveService { static func save(capture: CaptureItem, displayLabel: String, sessionDirectory: URL, settings: HotkeySettings) throws -> URL }
// Editor → Shell (smoke)
extension AnnotationCanvasView { static func smokeVerifyHoverManipulation(image: CGImage) -> Bool }
extension OverlayEditorController { func smokeRunNoteAffordanceProbe() -> Bool /* one-shot comment */; @discardableResult func smokeCreateComment(at point: CGPoint, note: String?) -> SBGuid? }
// Imaging (editor), используется автосохранением
enum ArrowDrawing { static func draw(in ctx: CGContext, from: CGPoint, to: CGPoint, color: CGColor, thickness: CGFloat, style: String); static func sampleImage(style: String, size: NSSize) -> NSImage }
```
