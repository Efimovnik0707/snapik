# SPEC-DELTA-2A: дизайн транспорта на macOS (раздел A)

Поправка к дизайну ниже (решение принято): жест «альтернативный» на macOS это **Ctrl+V** (так Claude Code вставляет картинки на Mac), Option+V принимается тоже. Значит `PasteIntentGesture` получает третий кейс `.controlV`, `PasteIntentKeyState` перестаёт отбрасывать Control как «лишний модификатор» (Control без Cmd/Option = жест `.controlV`), `InputInjecting.injectPaste` принимает жест (`PasteIntentGesture`), а не `alternate: Bool` (оставить `alternate:`-перегрузку как обёртку), `MacInputInjector` умеет постить Ctrl+V (`kVK_Control = 0x3B`, флаг `.maskControl`). Задержка per-image для `.controlV` и `.optionV` = 1.2 с, для `.commandV` = 0.7 с. Текст всегда Cmd+V.

## 0. Что уже есть и что расходится с Windows

| Windows (эталон) | macOS сейчас | Разрыв |
|---|---|---|
| `WindowsPasteIntentObserver(Func<PasteIntentObserved,bool> shouldIntercept)`, хук возвращает 1 (проглатывает) | `MacPasteIntentObserver.swift:55-66` `.listenOnly`, callback всегда возвращает событие | A.1, A.6 |
| `PasteIntentObserved.IsIntercepted` | `PasteIntent` (`TransportContracts.swift:203-223`) без поля | A.1 |
| `PasteIntentInterceptionState` (`WindowsPasteIntentObserver.cs:167-185`) | нет | A.6 |
| `CompleteSequentialAsync` + 3 задержки (500/700/1200 мс) | только `complete` (Codex), одна задержка | A.2 |
| `SetPngGuardedAsync` = PNG + DIB + Bitmap (без FileDrop) | `setPNGGuarded` = отдельный item `.fileURL` + отдельный item `.png/.tiff` | A.2 |
| `RepublishPackageForReuseAsync`, `_pasteObservedForCurrentPackage`, ротация в `EnsureCurrentCaptureSessionAsync` | `completePasteIntent` ротирует сразу (`AppCoordinator+Package.swift:272-274`) | A.3 |
| `ClipboardEchoDetector` + `WatchForReceiverEchoAsync` (6 с / 200 мс) | нет | A.4 |
| `StartupTrace` строки `PasteIntent …`, `Clipboard diagnostics` | `StartupLog` есть, строк нет | A.5 |
| `_clipboardPublicationGate` (SemaphoreSlim 1,1) | нет (только `isCompletingPasteIntent`) | A.3 |

`ClipboardSnapshot` (`TransportContracts.swift:93-107`) уже имеет `hasText/text/filePaths/hasImage`; для эхо-детектора нужен computed `hasFiles` и строгая выборка file-URL в `captureCore`.

## 1. Перехват с проглатыванием (`MacPasteIntentObserver`)

### 1.1 Разрешения и выбор режима tap
Активный tap (`.defaultTap`) на `.cgSessionEventTap` требует Accessibility (`AXIsProcessTrusted`); listen-only требует Input Monitoring (`CGPreflightListenEventAccess`). Чистая функция:
```swift
public enum PasteIntentTapMode: Equatable { case intercepting, listenOnly }
public static func preferredTapMode(accessibility: Bool, inputMonitoring: Bool) -> PasteIntentTapMode? {
    if accessibility { return .intercepting }
    if inputMonitoring { return .listenOnly }
    return nil
}
public private(set) var tapMode: PasteIntentTapMode?
```
`start()`: 1) `mode = preferredTapMode(...)`; `nil` → `permissionMissing("Отслеживание вставки недоступно: нет разрешения Input Monitoring.")`. 2) `tapCreate(options: mode == .intercepting ? .defaultTap : .listenOnly)`; если при `.defaultTap` вернулся `nil` — повторить с `.listenOnly`, только потом бросать. 3) записать `tapMode`, `onDiagnostic?("PasteIntent tap mode: \(mode) (accessibility=…, inputMonitoring=…)")`.
Без Accessibility перехвата нет: интенты приходят с `intercepted == false`, координатор идёт старым путём (Codex `complete` → ротация / `.notApplicable` → ротация при `stillOurs`).
Запрос Accessibility: `TransportPermissions.requestAccessibilityAccess()` один раз в `AppCoordinator.start()` при `!options.demo && !options.smokeTest`.

### 1.2 Сигнатура и callback
```swift
public init(foreground: ForegroundTargetServicing, clipboardSequence: @escaping () -> Int,
            shouldIntercept: ((PasteIntent) -> Bool)? = nil)
public var onDiagnostic: ((String) -> Void)?
```
Callback возвращает `Unmanaged<CGEvent>?`: `nil` = проглотить. `handle(type:event:) -> Bool` (suppress):
```swift
fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
    if Self.isOwnEvent(event) { return false }                 // свои синтетические всегда пропускать
    if targetPid == ownPid { return false }                    // собственный процесс
    switch type {
    case .flagsChanged: keyState.observeModifier(...); return false
    case .keyDown, .keyUp:
        guard keyCode == V else { return false }
        let gesture = keyState.observeV(isKeyDown:, isInjected: false)   // nil на autorepeat
        var intercept = false; var intentToPublish: PasteIntent?
        if let gesture, type == .keyDown {
            let target = foreground.currentTarget()
            var intent = PasteIntent(gesture: gesture, …, target: target, clipboardSequence: clipboardSequence(), intercepted: false)
            intercept = tapMode == .intercepting && onPasteIntent != nil && target != nil && (shouldIntercept?(intent) ?? false)
            if intercept { intent = PasteIntent(…, intercepted: true) }
            intentToPublish = intent
        }
        let suppress = interceptionState.shouldSuppress(isVKey: true, isKeyDown: type == .keyDown, isInjected: false, interceptThisGesture: intercept)
        if let intentToPublish { DispatchQueue.main.async { self.onPasteIntent?(intentToPublish) } }
        return suppress
    case .tapDisabledByTimeout, .tapDisabledByUserInput: /* re-enable */ return false
    }
}
```
- Предикат вызывается синхронно в callback; источник tap на `CFRunLoopGetMain()`, callback выполняется на главном потоке, но для компилятора это nonisolated-контекст, поэтому в координаторе оборачивать в `MainActor.assumeIsolated { … }`. Не использовать `DispatchQueue.main.sync`.
- `intent.target` берётся один раз в callback и передаётся в предикат.
- Autorepeat: `keyState.observeV` возвращает `nil` при `vDown`, но `interceptionState.shouldSuppress` продолжает подавлять до keyUp.
- keyUp V не глотать (как на Windows; сброс флага).
- Исключение Codex Desktop — в предикате координатора: `BuiltInTargetProfiles.codexDesktop.matches(target)` → `intercept = false`.
- Собственный процесс: `.eventTargetUnixProcessID` (уже есть) плюс `.eventSourceUnixProcessID == ownPid`.

### 1.3 Свои события
```swift
static func isOwnEvent(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == MacInputInjector.syntheticEventTag
        || pid_t(event.getIntegerValueField(.eventSourceUnixProcessID)) == ProcessInfo.processInfo.processIdentifier
}
```
Критично: инъекция через `.cghidEventTap` проходит через наш session-tap; без первой проверки `.defaultTap` проглотит собственный Cmd+V.

### 1.4 Core: `PasteIntentInterceptionState` (в `PasteIntentKeyState.swift`)
```swift
public final class PasteIntentInterceptionState {
    public init()
    public func shouldSuppress(isVKey: Bool, isKeyDown: Bool, isInjected: Bool, interceptThisGesture: Bool) -> Bool
    public func reset()
}
```
Логика 1:1 с `WindowsPasteIntentObserver.cs:171-184`; `stop()` вызывает `reset()` обоих состояний.

### 1.5 Core: `PasteIntent.intercepted`
`public let intercepted: Bool`, в init default `false`.

## 2. Core: `completeSequential` в `CodexDesktopPasteCompletionService`
```swift
public static let defaultSettlementDelay: TimeInterval = 0.5
public static let defaultImageSettlementDelay: TimeInterval = 0.7
public static let defaultAltVImageSettlementDelay: TimeInterval = 1.2
public init(clipboard:, foreground:, input: GuardedInputInjecting, codexProfile: = BuiltInTargetProfiles.codexDesktop,
            settlementDelay: = …, imageSettlementDelay: = …, altVImageSettlementDelay: = …, scheduler: = DispatchQueueScheduler())
public func completeSequential(intent: PasteIntent, ownedPackageReceipt: ClipboardSnapshot, immutableImagePaths: [String],
            immutablePromptText: String, cancellationToken: PasteCancellationToken = .init(),
            completion: @escaping (CodexPasteCompletionResult) -> Void)
```
Шаги (порт `CodexDesktopPasteCompletionService.cs:121-205`, CPS-стиль как `PasteCoordinator.stageImage`):
1. `target = foreground.currentTarget()` синхронно. Guard: `intent.intercepted`, `target != nil`, `intent.target != nil`, `target == intent.target`, `!codexProfile.matches(target)`; иначе `.notApplicable` "Intercepted paste completion applies only to a physical Ctrl+V or Alt+V outside Codex Desktop."
2. `intent.clipboardSequence != ownedPackageReceipt.sequence` → `.staleIntent`.
3. пусто → `.nothingToDispatch` "The package needs at least one image and prompt text."
4. `perImageDelay = intent.gesture == .commandV ? imageSettlementDelay : altVImageSettlementDelay`.
5. `stageImage(index:expectedSequence:currentReceipt:)` рекурсивно: проверка отмены → `.cancelled` "The guarded sequential paste was cancelled."; `clipboard.setPNGGuarded(path, expectedSequence)`; `.failure` → `.clipboardChanged`; `sendGuarded(gesture: intent.gesture, target:, receipt:)` (finalGuard = capture→sequence, currentTarget→==); отказ → `guardRejectedResult(status, "image \(i+1)", receipt)`: "\(targetLost ? "Claude focus changed" : "The clipboard changed") while the image N paste keys were being released."; `scheduler.schedule(after: perImageDelay)`; после — проверка отмены; `capture` seq ≠ → `.clipboardChanged` "The clipboard changed after image N paste."; `currentTarget() != target` → `.targetLost` "Focus changed after image N paste."
6. Текст: `setTextGuarded(prompt, expected: currentReceipt.sequence)`; `sendGuarded(gesture: .commandV)`; отказ → `guardRejectedResult(_, "text", textReceipt)`; успех → `.completedUnverified` "Image and prompt paste shortcuts were dispatched in order; receiver acceptance was not observable."
`complete` (Codex): guard `!intent.intercepted` → `.notApplicable`. `CodexPasteCompletionResult.currentClipboardReceipt` = alias `textClipboardReceipt`.
Фейки: вынести из `CodexDesktopPasteCompletionServiceTests.swift` в `Tests/SnapikCoreTests/Transport/TransportFakes.swift`; `FakeClipboard.writes: [String]` («PACKAGE:a,b» / путь / «TEXT»), `setPNGGuarded`/`setPackageGuarded` реальные, `externalWrite()`; `FakeInput.afterDispatch`.

## 3. `MacClipboardService`
### 3.1 `setPNGGuarded`: один `NSPasteboardItem` с `.png`, `.tiff`, `.fileURL` (в этом порядке)
`.png` — Chromium/Electron и `pngpaste`/Claude Code; `.tiff` — универсальный растр AppKit (`NSImage(pasteboard:)`); `.fileURL` — получатели, принимающие только вложения. Один item, чтобы получатель выбрал лучший тип внутри item'а. Риск: Terminal.app по Cmd+V с `.fileURL` может вставить путь текстом → параметр `init(..., pngItemIncludesFileURL: Bool = true)` для отката. `setPackageGuarded` для одного файла собирать тем же helper'ом `pngItem(for:)` плюс text item.
### 3.2 `captureCore`
`filePaths`: `readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`; `hasImage` как сейчас; `ClipboardSnapshot.hasFiles { !filePaths.isEmpty }`; `diagnosticTypes() -> [String]`.

## 4. Многоразовый пакет и ротация (`AppCoordinator`)
Новый файл `Sources/SnapikMac/App/AppCoordinator+PasteIntent.swift` (из `+Package.swift` уходят `handlePasteIntent`/`completePasteIntent`).
Состояние в `AppCoordinator.swift`:
```swift
var pasteObservedForCurrentPackage = false
var pasteIntentTransition: Task<Void, Never>?
let clipboardPublicationGate = AsyncGate()     // порт SemaphoreSlim(1,1): isBusy + wait()/release()
var receiverEchoWatchTask: Task<Void, Never>?
```
`AsyncGate` (`App/AsyncGate.swift`): очередь `CheckedContinuation`, `var isBusy`, `func wait() async`, `func release()`.
Предикат (`App/PasteInterceptPredicate.swift`):
```swift
struct PasteInterceptState { var resetting, transitionInFlight, gateBusy: Bool; var ownedSequence: Int?; var promptPresent, preparedPresent: Bool }
enum PasteInterceptPredicate { static func evaluate(intent: PasteIntent, state: PasteInterceptState, codexProfile: TargetProfile) -> (intercept: Bool, log: String) }
```
В `init`: `MacPasteIntentObserver(foreground:clipboardSequence:shouldIntercept: { [weak self] intent in MainActor.assumeIsolated { self?.shouldInterceptPasteIntent(intent) ?? false } })`. Лог из предиката через `DispatchQueue.main.async { StartupLog.write(...) }`.
Методы:
- `handlePasteIntent`: лог «observed»; seq ≠ → `logClipboardDiagnostics()` и выход; `promptAtIntent == nil` → статус; guard `!isSessionResetting`, `pasteIntentTransition == nil`, `!gate.isBusy`, `ownedClipboardReceipt == receiptAtIntent`; `pathsAtIntent = prepared?.imagePathsInOrder().map(\.path) ?? []`; `pasteIntentTransition = Task { await completePasteIntent(...); pasteIntentTransition = nil }`.
- `completePasteIntent`: `await gate.wait(); defer release`; `intent.intercepted ? completeSequential : complete`; лог «completion»; guard свежести receipt; обновить receipt; `.completedUnverified` → `republishPackageForReuse`; `!intercepted && .notApplicable` → `stillOurs` → `startNewSession()`; иначе статус «Снимки сохранены, но вставка не завершена: …» (привести `StatusStrings.swift:16` к Windows-тексту).
- `republishPackageForReuse(paths:prompt:)`: guard receipt & prepared → статус «Пакет вытеснен…»; `setPackageGuarded(paths, prompt, expected: current.sequence)`; receipt/prompt; `pasteObservedForCurrentPackage = true`; лог «republished»; статус «Вставлено: {0} изображений · {1} заметок. …» (подстановка `{0}`/`{1}`); `startReceiverEchoWatch`. `clipboardChanged` → `cancelReceiverEchoWatch()`, обнулить receipt/prompt, статус «Пакет вытеснен другим приложением. Сессия сохранена.».
- `ensureCurrentCaptureSession` (`AppCoordinator.swift:213-226`): первым блоком `if pasteObservedForCurrentPackage { сброс; cancelReceiverEchoWatch(); receipt/prompt = nil; return await startNewSession() }`.
- `newCapture`/`saveFullscreen`/`openCapture`: вместо `guard !isCompletingPasteIntent { return }` — `await pasteIntentTransition?.value`.
- `startNewSession`, `saveAndCopyCommittedPackage`, `refreshOwnedClipboard`, `shutdown`: `cancelReceiverEchoWatch()`; `startNewSession` также сбрасывает флаг. `saveAndCopyCommittedPackage`/`refreshOwnedClipboard` под `gate`.

## 5. Эхо-наблюдатель
Core `Sources/SnapikCore/Transport/ClipboardEchoDetector.swift`:
```swift
public enum ClipboardEchoDetector {
    public static func isReceiverEcho(_ snapshot: ClipboardSnapshot, promptText: String) -> Bool
    static func normalize(_ text: String) -> String
}
```
Правила 1:1: пустой prompt → false; `hasFiles` → false; `hasImage` → false; `text == nil` → false; normalize = `NSRegularExpression("\\[Image #\\d+\\]")` → "", `"\\s+"` → " ", trim; пусто → false; `==` или `contains`.
Mac (`AppCoordinator+PasteIntent.swift`): `receiverEchoWatchWindow = 6`, `receiverEchoPollInterval = 0.2`; `startReceiverEchoWatch(paths:prompt:)`, `cancelReceiverEchoWatch()`, `watchForReceiverEcho` (цикл как 4.7 Части 1; `Task.sleep`; `await gate.wait()` перед ре-публикацией; дедлайн += 6 с; в `defer` обнулить task, если это всё ещё наш, по `UUID`-токену).

## 6. Диагностика в `StartupLog`
Строки дословно как в Части 1 §4.8, жест печатать `CmdV`/`CtrlV`/`OptionV`; `Clipboard diagnostics: seq=…, owner=n/a, formats=[public.png,…], text=…` (превью ≤120, `\r`→` `, `\n`→`|`); Mac-only `PasteIntent tap mode: intercepting|listenOnly (accessibility=…, inputMonitoring=…)`, `PasteIntent tap re-enabled after …`. `gate` печатать как `1`/`0`.

## 7. Тесты
Core `Tests/SnapikCoreTests/Transport/`: `TransportFakes.swift`; `SequentialPasteCompletionServiceTests.swift`: `testInterceptedCommandVInArbitraryAppDispatchesOrderedPngImagesThenTextViaCommandV` (1 и 3 картинки), `testInterceptedControlVInTerminalDispatchesImagesViaControlVThenTextViaCommandV` (1 и 3), `testInterceptedOptionVDispatchesImagesViaOptionV`, `testUninterceptedIntentDoesNotWriteOrInject`, `testInterceptedCodexDesktopIntentStaysOnCompletePathDoesNotWriteOrInject`, `testFocusChangeDuringPhysicalReleaseStopsBeforeAnyPasteShortcut`, `testFocusLossAfterFirstImagePasteReturnsCurrentReceiptAndStopsSequence`, `testClipboardChangeAfterFirstImagePasteStopsBeforeSecondImageAndText`, `testCancellationAfterFirstImagePasteReturnsCurrentReceiptWithoutContinuing`, `testInterceptedIntentIsNotAlsoHandledByCodexCompletion`, `testReusablePackageRepublishesFullPackageAfterCompletedPasteAndAcceptsNextIntent`, `testReusablePackageDisplacedByAnotherAppLeavesClipboardUntouched`, `testStaleIntentAndEmptyPackageDoNotWriteOrInject`; `ClipboardEchoDetectorTests.swift` (5); `PasteIntentKeyStateTests.swift` +3 (`testInterceptedPhysicalVSuppressesInitialAndRepeatKeyDownsUntilRelease`, `testInterceptionNeverSuppressesInjectedOrUnrelatedKeys`, `testInterceptedPhysicalControlVSuppressesGestureAndOwnInjectedReleaseIsNotSuppressed`, плюс тест что Ctrl+V распознаётся как `.controlV`).
Mac `Tests/SnapikMacTests/`: `Transport/TransportMacTests.swift` +4 (`testSetPNGGuardedWritesPngTiffAndFileURLInSingleItem`, `testCaptureReportsFilesTextAndImageForEchoDetector`, `testPreferredTapModeDegradesFromInterceptingToListenOnlyToNil`, `testOwnSyntheticEventIsRecognizedByTagAndSourcePid`); `App/PasteInterceptPredicateTests.swift` (4).

## 8. Порядок шагов
1. Core контракты (`PasteIntent.intercepted`, `PasteIntentGesture.controlV`, `PasteIntentInterceptionState`, `hasFiles`, `currentClipboardReceipt`, `ClipboardEchoDetector`). 2. Core сервис `completeSequential`. 3. Core тесты. 4. `MacClipboardService`. 5. `MacPasteIntentObserver`. 6. `AppCoordinator` (`AsyncGate`, `PasteInterceptPredicate`, `+PasteIntent.swift`, правки `ensureCurrentCaptureSession`/`newCapture`/`startNewSession`/`shutdown`, статусы, запрос Accessibility в `start()`). 7. Mac тесты, README, `SYNC.md`.

## 9. Риски
1. Свои события и `.defaultTap` (см. 1.3). 2. Таймаут callback: `AXUIElementSetMessagingTimeout(appElement, 0.1)` в `MacForegroundTargetService`; логирование асинхронно. 3. Разрешения: `CGPreflightListenEventAccess` может быть false при выданном Accessibility, не гейтить `.defaultTap` на Input Monitoring; ad-hoc подпись сбрасывает TCC после пересборки; при `tapCreate == nil` деградация, не краш. 4. Option+V вводит «√» в терминале — поэтому Ctrl+V основной альтернативный жест (см. поправку вверху). 5. `.fileURL` в png-item: параметр отката. 6. `MainActor.assumeIsolated` корректен только потому, что источник на `CFRunLoopGetMain()`. 7. Эхо на macOS, вероятно, no-op; оставляем для паритета.

## 10. Не переносится 1:1
Владелец буфера (`owner=n/a`, вместо него changeCount + types + превью); `ClipboardSnapshot.Data` → плоские флаги; `LLKHF_INJECTED` → тег + source-pid; двухуровневый TCC; `hwnd/pid` → `ForegroundTarget ==`; `SemaphoreSlim` → `AsyncGate`.

## Файлы
Новые: `Sources/SnapikCore/Transport/ClipboardEchoDetector.swift`, `Sources/SnapikMac/App/AppCoordinator+PasteIntent.swift`, `Sources/SnapikMac/App/PasteInterceptPredicate.swift`, `Sources/SnapikMac/App/AsyncGate.swift`, `Tests/SnapikCoreTests/Transport/TransportFakes.swift`, `Tests/SnapikCoreTests/Transport/SequentialPasteCompletionServiceTests.swift`, `Tests/SnapikCoreTests/Transport/ClipboardEchoDetectorTests.swift`, `Tests/SnapikMacTests/App/PasteInterceptPredicateTests.swift`.
Изменяемые: `Sources/SnapikCore/Transport/TransportContracts.swift`, `PasteIntentKeyState.swift`, `CodexDesktopPasteCompletionService.swift`, `Sources/SnapikMac/Transport/MacPasteIntentObserver.swift`, `MacClipboardService.swift`, `MacInputInjector.swift`, `MacForegroundTargetService.swift`, `Sources/SnapikMac/App/AppCoordinator.swift`, `AppCoordinator+Package.swift`, `StatusStrings.swift`, тесты, `CONTRACTS.md`, `README.md`, `SYNC.md`.
