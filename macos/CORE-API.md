# SnapikCore — API summary

Port of `src/Snapik.Core/**` + `src/Snapik.Infrastructure/**` (+ settings/i18n data from
`src/Snapik.App`). Foundation-only, no AppKit/CoreImage/UIKit. Builds on Windows Swift 6.3 and
macOS Swift 6.1, `swift-tools-version: 5.9` (Swift 5 language mode, no actors/Sendable checking
forced). Every file has a `// port of <C# path>` doc comment citing its source.

## Identity, dates, errors (`Support/`)

- **`SBGuid`**: port of `Guid`. `.description` = lowercase `8-4-4-4-12` (matches .NET default
  `ToString()`/`"d"`); `.digitsLowercase` = 32-char lowercase hex, no dashes (matches
  `Guid.ToString("N")`, used in file/dir names). `SBGuid.empty` = `Guid.Empty`. `Codable` (encodes
  as the lowercase-dashed string), `Hashable`, `Equatable`.
- **Dates** are plain Foundation `Date` (no wrapper type). `SnapikJson.encoder/decoder` encode
  them as `"yyyy-MM-ddTHH:mm:ss.fffffff+00:00"` (.NET `DateTimeOffset` "O" format, always UTC —
  the app only ever uses zero-offset instants). Implemented in `ISO8601Precise` via pure integer
  civil-calendar math (no `Calendar`/`TimeZone`), so it doesn't depend on ICU support.
- **`SnapikError`**: one enum standing in for every C# exception type thrown in the ported
  code: `.invalidData`, `.argument`, `.argumentOutOfRange`, `.argumentNull`, `.keyNotFound`,
  `.invalidOperation`, `.fileNotFound`, each `(String)`. Switch on the case to distinguish, as
  the C# tests do with `Assert.Throws<T>`.
- **`TimeProvider`** protocol (`func utcNow() -> Date`) + `SystemTimeProvider`: port of .NET
  `TimeProvider`/`TimeProvider.System`, injectable into `SessionHistory` and `FileExportService`.
- **`RelativePathValidation.isRelativeAndSafe(_ path: String) -> Bool`**: port of the
  `Path.IsPathRooted(...) || path.Split(...).Contains("..")` checks.
- **`SHA256`**: pure-Swift SHA-256 (no CryptoKit — Apple-only). `SHA256.hash(Data) -> [UInt8]`,
  `SHA256.hexString(Data) -> String` (lowercase hex, port of `Convert.ToHexStringLower`).

## Models (`Models/`)

- **`AnnotationKind`**: `String, Codable` enum — `.arrow .rectangle .highlight .freehand .text
  .redaction .blur .comment` (`.comment` added in sync 2, SPEC-DELTA-2B §B — a pin-shaped note
  linked to another annotation or the capture itself, no geometry drawn on screen/export). Raw
  values equal case names (already camelCase for JSON).
- **`NormalizedPoint(x: Double, y: Double)`** — `Codable`, JSON keys `x`, `y`.
- **`AnnotationItem`**: `id: SBGuid, kind: AnnotationKind, points: [NormalizedPoint],
  strokeColor: String, thickness: Double, text: String, note: String, pathSegments:
  [[NormalizedPoint]], parentAnnotationId: SBGuid?, arrowStyle: String`.
  `.create(kind:points:strokeColor:thickness:text:note:parentAnnotationId:arrowStyle:) ->
  AnnotationItem` (defaults: `strokeColor: "#FF3B30"`, `thickness: 3`, `parentAnnotationId: nil`,
  `arrowStyle: "straight"`). `.getPathSegments() -> [[NormalizedPoint]]` — returns `pathSegments`
  if non-empty, else `[points]` (or `[]` if `points` empty too). JSON decode tolerates missing
  `pathSegments`/`parentAnnotationId`/`arrowStyle` keys (pre-sync-2 sessions), defaulting to `[]`/
  `nil`/`"straight"` respectively. `parentAnnotationId` (sync 2, SPEC-DELTA-2B §B): GUID of the
  annotation a `.comment` is visually linked to; `nil` means linked to the capture itself.
  `arrowStyle` (sync 2): `"straight"` (default) / `"curved"` / `"bold"` / `"wide"`, consumed by
  `Imaging/ArrowDrawing.swift` (Mac app target, out of Core's scope) for `.arrow` rendering.
- **`CaptureItem`**: `id: SBGuid, sourceImagePath: String, pixelWidth/pixelHeight: Int,
  dpiX/dpiY: Double, title: String, note: String, annotations: [AnnotationItem]`.
  `.create(sourceImagePath:pixelWidth:pixelHeight:dpiX:dpiY:title:note:) -> CaptureItem` (dpi
  defaults 96, empty `annotations`).
- **`SnapikSession`**: `id: SBGuid, schemaVersion: Int, createdAtUtc/modifiedAtUtc: Date,
  revision: Int, globalNote: String, selectedTargetProfileId: String?, captures: [CaptureItem]`.
  `SnapikSession.currentSchemaVersion == 1`. `.create(nowUtc:) -> SnapikSession`.
- **`SessionValidation.validate(_ session: SnapikSession) throws`**: id/schema/revision
  checks, capture id uniqueness + relative-path safety + positive dimensions/DPI, annotation id
  uniqueness + positive thickness + points in `[0,1]` + path-segment kind/length/range rules.
  Throws `SnapikError.invalidData`.

All model types are `Codable, Equatable, Sendable`; JSON field names are camelCase versions of
the property names (`sourceImagePath`, `pixelWidth`, `dpiX`, `createdAtUtc`, ...) — schema-
compatible with the C# `SnapikJson.Options` (`JsonNamingPolicy.CamelCase`).

## Editing (`Editing/`)

- **`NormalizedRect(x:y:width:height:)`**: `.left .top .right .bottom` computed. Not `Codable`
  (ephemeral crop-bounds input, never persisted).
- **`CaptureCropper.crop(source:cropBounds:croppedSourceImagePath:croppedPixelWidth:
  croppedPixelHeight:) throws -> CropResult`** (`{ previousCapture, croppedCapture,
  removedAnnotationIds: [SBGuid] }`). Liang-Barsky-style line/box/polyline clipping identical to
  the C# port: arrows clip as lines, rectangle/text/redaction/blur/**comment** (sync 2) clip as
  boxes, freehand/highlight clip as multi-run polylines (disjoint visible runs preserved
  separately, never rejoined). Throws `.argumentOutOfRange`/`.argument` for invalid crop bounds or
  paths. Sync 2 (SPEC-DELTA-2B §B): a retained annotation whose `parentAnnotationId` pointed at an
  annotation the crop removed has its link cleared (`nil`) instead of being removed itself.
- **`SessionHistory`** (class): `init(initial:timeProvider:)`, `.current` (get-only),
  `.canUndo/.canRedo`, `.apply(_ op: (SnapikSession) throws -> SnapikSession) rethrows`
  (pushes onto undo stack + clears redo unless `op` returns an equal session), `.undo()/.redo()
  -> Bool` (restore + bump revision + re-stamp `modifiedAtUtc` via `timeProvider`). Backed by
  Swift arrays as LIFO stacks (`append`/`removeLast`), no actors.
- **`SessionOperations`**: `addCapture`, `removeCapture`, `moveCapture(_:captureId:
  destinationIndex:nowUtc:)`, `updateGlobalNote`, `updateCapture` — all `throws ->
  SnapikSession`, each bumping `revision`/`modifiedAtUtc` and re-validating via
  `SessionValidation`. `removeCapture`/`updateCapture`/`moveCapture` throw
  `.keyNotFound`/`.argumentOutOfRange` for unknown ids / bad indices.

## Exporting (`Exporting/`)

- **`ExportText.hasContent(_ value: String?) -> Bool`** — non-nil and not all-whitespace.
- **`CaptureLabels.forIndex(_ i: Int) throws -> String`** — bijective base-26 (sync 2,
  SPEC-DELTA-2B §B): 0→"A" … 25→"Z", 26→"AA", 299→"KN", unbounded above; throws
  `.argumentOutOfRange` only for `i < 0`. `.forAnnotation(captureLabel:oneBasedIndex:) -> String`
  ("A" + 1 → "A1"), `.forNotedAnnotations(captureLabel:capture:) -> [LabeledAnnotation]` (only
  annotations with non-blank notes, numbered in order).
- **`PromptGenerator().generate(_ session: SnapikSession) throws -> String`** — Russian prompt
  text verbatim from the C# port ("Общее пожелание:", "Снимок {label}", "Комментарий к снимку:",
  `"{label}: {note}"` per noted annotation), sections joined by `"\n\n"`. Sync 2 (SPEC-DELTA-2B
  §B): a noted annotation whose `parentAnnotationId` points at another *numbered* (non-blank-note)
  annotation gets a `" (к области <МЕТКА_РОДИТЕЛЯ>)"` suffix appended to its line.
- **`ExportImageEntry`/`ExportManifest`/`PreparedExport`/`ExportImageContext`**: `Codable` data
  contracts, camelCase JSON fields matching the C# port 1:1 (`captureId`, `displayLabel`,
  `fileName`, `sha256`, `byteLength`, `exportId`, `sessionId`, `promptFileName`, `promptSha256`,
  `promptText`, `captureCount`, `noteCount`). `PreparedExport.imagePathsInOrder() -> [URL]`.
- **`ExportImageRendering` protocol** (implement in the Mac app target — pixel rendering is
  explicitly out of Core's scope):
  ```swift
  protocol ExportImageRendering {
      func renderPNG(capture: CaptureItem, annotations: [AnnotationItem],
                      context: ExportImageContext) async throws -> Data
  }
  ```
  Returns full PNG bytes (not a `Stream`, unlike the C# `IExportImageRenderer` — simpler surface
  for a Foundation-only Core; `FileExportService` validates the PNG signature, hashes, and writes
  the file itself).
- **`ExportService` protocol** / **`FileExportService`** (the concrete implementation):
  `prepare(session:sessionDirectory: URL) async throws -> PreparedExport`. Stages into
  `exports/.staging-{exportId:N}`, validates each rendered PNG signature, writes `prompt.md` +
  `manifest.json`, then atomically `moveItem`s to `exports/revision-{rev:06d}-{exportId:N}`; on
  any failure the staging directory is removed and nothing partial is published. Throws
  `.invalidOperation` (no captures), `.fileNotFound` (missing source image), `.invalidData`
  (renderer didn't produce a PNG, or a capture path escapes the session directory).

## Persistence (`Persistence/`, `Paths/`, `Serialization/`)

- **`SessionStore` protocol** (port of `ISessionStore`): `getSessionDirectory(sessionId:) ->
  URL`, `save(_:) async throws`, `load(sessionId:) async throws -> SnapikSession?`.
- **`SessionAssetStore` protocol** (port of `ISessionAssetStore`):
  `saveOriginalPNG(sessionId:captureId:pngContent: Data) async throws -> String` (relative path).
- **`JsonSessionStore`** (the `SessionStore` implementation): `init(sessionsRoot: URL)`,
  `.createDefault()`. Directory layout: `{sessionsRoot}/{sessionId:N}/session.json`. Saves go
  through a temp file (`.session-{guid:N}.tmp`) + atomic replace. Concurrent `save` calls for the
  same session are serialized with `NSLock` (no actors) and use a monotonic sequence counter so
  the persisted file always reflects the highest-sequence call, mirroring the C#
  `SemaphoreSlim`-based "latest write wins" guarantee — see the caveat in
  `PersistenceAndExportTests.swift` about Swift's weaker task-ordering guarantees vs. C#'s
  synchronous-until-first-`await` semantics.
- **`DefaultSessionAssetStore`** (the `SessionAssetStore` implementation; renamed from C#'s
  `SessionAssetStore` to avoid clashing with the protocol name): writes
  `{sessionDir}/source/{captureId:N}.png` via temp file + PNG-signature validation + atomic
  replace; relative path returned uses `/` (not an OS-specific separator).
- **`SnapikPaths`**: `.defaultSessionsDirectory() -> URL` — macOS:
  `~/Library/Application Support/Snapik/sessions`; Windows: `%LOCALAPPDATA%\Snapik\sessions`
  (falls back to temp dir if unset); other platforms: `~/.snapik/sessions` (compile-only
  fallback, Snapik doesn't ship there). `.sessionsDirectory(dataDirectory: URL?) -> URL` —
  port of the app's `--data-dir` / `SNAPIK_DATA_DIR` override (explicit dir wins, else
  default).
- **`SnapikJson.encoder` / `.decoder`**: shared `JSONEncoder`/`JSONDecoder` for
  `SnapikSession` and `ExportManifest` — pretty-printed, custom `Date` strategy (see above).
  Do **not** use these for `HotkeySettings` (different on-disk format, see below).

## Settings / i18n (`Settings/`)

- **`UiLanguage`**: `.current: String` ("ru"/"en"), `.text(_:language:) -> String` — the RU/EN
  string table ported verbatim from `src/Snapik.App/UiLanguage.cs` (~92 pairs after sync 2:
  menu items, tool names, dialog labels, notification text, plus the preview window/comments/
  arrow-style/auto-save strings added by SPEC-DELTA-2.md §3). The WPF view-tree walker
  (`UiLanguage.Apply`) was **not** ported (AppKit-specific UI plumbing, out of Core's scope) — the
  Mac app target should localize its own view tree using `UiLanguage.text(_:language:)`.
- **`HotkeyModifiers`**: `OptionSet<UInt32>` — `.alt = 0x1, .control = 0x2, .shift = 0x4,
  .windows = 0x8, .noRepeat = 0x4000` (bit-identical to `Snapik.Windows.HotkeyModifiers`, kept
  only so persisted `"custom:{modifiers}:{key}"` id strings stay numerically comparable across
  builds).
- **`HotkeyChoice(id: String, label: String)`**.
- **`HotkeySettings`**: `captureId, pasteId: String` (required) plus defaulted fields
  `captureEnabled(true), fullscreenSaveEnabled(false), fullscreenSaveId("custom:4:44"),
  showNotifications(true), rememberRegion(false), captureCursor(false), saveFormat("png"),
  jpegQuality(90), saveDirectory(~/Pictures/Snapik), language("ru"), autoSaveCaptures(false),
  playSounds(true)`. The last two are sync 2 additions (SPEC-DELTA-2B §B/§E4).
  `.default`, `.choices`/`.pasteChoices: [HotkeyChoice]` (same ids/labels as the C# `Choices`),
  `.find(_ id: String) -> HotkeyChoice`. **JSON is PascalCase** (`CaptureId`, `SaveDirectory`,
  `AutoSaveCaptures`, `PlaySounds`, ...) — the C# `Save`/`Load` use a *default*
  `JsonSerializerOptions` (no camelCase policy), unlike session/manifest JSON, so use plain
  `JSONEncoder()/JSONDecoder()`, not `SnapikJson`. `Codable` conformance uses an explicit
  `init(from:)`/`encode(to:)` (not the synthesized one): every field is `decodeIfPresent` with its
  own default, so a settings file missing any key — including the sync-2 `AutoSaveCaptures`/
  `PlaySounds` keys a pre-sync-2 file won't have — still decodes per-field instead of the whole
  `Decodable` conformance failing.
  `.load(path: URL) -> HotkeySettings` / `.save(path: URL) throws` — any decode failure (missing
  file, corrupt JSON) returns `.default`, matching the C# catch-all fallback.
  **Not ported**: `HotkeyGesture`/virtual-key → `Key` name mapping (`KeyInterop`,
  `RegisterHotKey`) is Win32-only API surface with no cross-platform equivalent; `.find` for a
  `"custom:..."` id reconstructs a modifier-only label (`"Ctrl + Alt + "`) with a `"VK 0x.."`
  fallback for the key portion. The Mac app target should map `id`/virtual-key numbers to its own
  Carbon/AppKit hotkey representation.

## Not ported (out of scope / no cross-platform equivalent)

- Image rendering with annotations baked in (`ExportImageRendering` is a protocol stub; Mac app
  implements it with CoreGraphics/CoreImage).
- `UiLanguage.Apply` (WPF `DependencyObject` tree walk) and all of `EditorModels.cs`
  (`BitmapSource`/`Color`/`Point`-based WPF editor state — not pure data, out of Core's scope).
- `HotkeyGesture`/`HotkeyModifiers`' Win32 registration path (`WindowsGlobalHotkeyService`,
  `KeyInterop`) — only the persisted-settings bit flags were ported, for JSON compatibility.

## Verification status

`swift build --target SnapikCore` could not be completed on this machine: even a bare
`import Foundation` fails to compile here (`error: header 'stdnoreturn.h' not found` while
building the `ucrt`/`SwiftOverlayShims` C module), reproduced outside the package with a
one-line `swiftc hello.swift` using the exact toolchain/env recipe from the task. Root cause
narrowed down to the installed Windows SDK (`10.0.19041.0`, from 2020) predating Microsoft
shipping `stdnoreturn.h` in `ucrt`; the installed MSVC (`14.29.30133`) doesn't have it either, and
the Swift toolchain's own copy (`.../usr/lib/swift/clang/include/stdnoreturn.h`) is on the search
path but isn't picked up by the `ucrt.modulemap` textual-header resolution. This blocks **any**
Foundation-importing Swift code on this machine, not just this package — confirmed unrelated to
the Core source. All 25 source files and 4 test files pass `swiftc -parse` (syntax-only, no
Foundation resolution needed) with zero errors. Fix requires installing a newer Windows 10/11 SDK
(≥ 10.0.20348, which ships `ucrt/stdnoreturn.h`) or otherwise repairing the toolchain — outside
this task's file-editing scope. Full type/build verification should happen either after that SDK
is installed, or via the macOS CI runner (`swift build && swift test`), per the task's own
documented fallback for Windows XCTest issues.
