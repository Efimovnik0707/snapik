import Foundation

/// Port of the `HotkeyModifiers` flags enum from `src/Snapik.Windows/TransportContracts.cs`.
/// Kept here (not in `Snapik.Windows`, which is Win32-only and out of Core's scope) purely as
/// pure data so `HotkeySettings`'s persisted `"custom:{modifiers}:{virtualKey}"` id strings stay
/// numerically compatible with the Windows build.
public struct HotkeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let none = HotkeyModifiers([])
    public static let alt = HotkeyModifiers(rawValue: 0x0001)
    public static let control = HotkeyModifiers(rawValue: 0x0002)
    public static let shift = HotkeyModifiers(rawValue: 0x0004)
    public static let windows = HotkeyModifiers(rawValue: 0x0008)
    public static let noRepeat = HotkeyModifiers(rawValue: 0x4000)
}

/// Port of `HotkeyChoice` (`src/Snapik.App/HotkeySettingsWindow.xaml.cs`), minus the
/// Windows-only `HotkeyGesture` (`KeyInterop`/virtual-key registration is Win32 API surface with
/// no Core-appropriate cross-platform equivalent; the Mac app target maps `id` to its own
/// Carbon/AppKit hotkey representation).
public struct HotkeyChoice: Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Port of `HotkeySettings` (`src/Snapik.App/HotkeySettingsWindow.xaml.cs`).
///
/// JSON persistence: the C# `Load`/`Save` use a *default* `JsonSerializerOptions`
/// (`WriteIndented = true` only — no camelCase naming policy, unlike `SnapikJson.Options`), so
/// the on-disk field names are the exact PascalCase property names (`CaptureId`, `PasteId`,
/// `CaptureEnabled`, ...). The `CodingKeys` below reproduce that verbatim so a settings file
/// written by either build can be read by the other.
public struct HotkeySettings: Codable, Equatable, Sendable {
    public var captureId: String
    public var pasteId: String
    public var captureEnabled: Bool = true
    public var fullscreenSaveEnabled: Bool = false
    public var fullscreenSaveId: String = HotkeySettings.defaultFullscreenSaveId
    public var showNotifications: Bool = true
    public var rememberRegion: Bool = false
    public var captureCursor: Bool = false
    public var saveFormat: String = "png"
    public var jpegQuality: Int = 92
    public var saveDirectory: String = HotkeySettings.defaultSaveDirectory()
    public var language: String = "ru"
    /// Port of `AutoSaveCaptures` (SPEC-DELTA-2B §B/§E4), default `false`.
    public var autoSaveCaptures: Bool = false
    /// Port of `PlaySounds` (SPEC-DELTA-2B §B/§E2), default `true`.
    public var playSounds: Bool = true
    /// How loud the interface sounds are, 0..100; each sound keeps its own gain on top.
    public var soundVolume: Int = SettingsMigration.defaultSoundVolume
    /// The schema version of this file; 0 is a file written before versions existed.
    public var settingsVersion: Int = 0
    public var stackTopmost: Bool = true
    /// The width of the strip window in points; the visible card is 20 narrower. Read back clamped
    /// to the minimum and to the working area of the screen the strip opens on, less the gap it
    /// keeps at the edge; there is no number above that.
    public var stackWidth: Double = StripResizeGeometry.defaultWidth
    /// The height of the capture list inside the strip, not the height of the window: the window
    /// derives its own height from this one.
    public var stackHeight: Double = StripResizeGeometry.defaultListHeight
    public var clearStackAfterPaste: Bool = false
    /// Whether clearing the strip and leaving the application ask before the captures of the session
    /// are deleted. Written only by the "Do not ask again" box of that dialog: the settings window
    /// does not show it. A file written before this key gets the question, as every older file does.
    public var confirmSessionDiscard: Bool = true
    public var annotationColor: String = "#FF3B30"
    /// Which set of twelve colours the editor offers: `standard`, `pastel` or the user's own.
    public var annotationPalette: String = "standard"
    /// Which half of the pencil capsule is armed: `pen` or `highlight`.
    public var annotationPencil: String = "pen"
    public var annotationThickness: Double = 4
    /// The width of the highlighter stroke, in image pixels; it has a scale of its own.
    public var annotationHighlightThickness: Double = 16
    /// The size a caption is typed in, in image pixels; the editor reads it back clamped to 8..96.
    public var annotationFontSize: Double = 20
    /// The frame the editor draws by default: `rectangle`, `rounded` or `ellipse`.
    public var annotationShape: String = "rectangle"
    /// How that frame is filled by default: `none`, `solid`, `translucent` or `blur`.
    public var annotationFill: String = "none"
    /// The colour inside that frame; empty means "the colour of the outline".
    public var annotationFillColor: String = ""
    /// Whether that frame carries an outline at all; a solid fill without one conceals.
    public var annotationOutline: Bool = true
    /// Where "Save package…" wrote the last time; empty means "wherever single captures go".
    public var packageSaveDirectory: String = ""
    public var packageCreateSubfolder: Bool = true
    /// The version of the first run wizard this file has already seen; 0 means "never".
    public var onboardingVersion: Int = 0
    public var theme: String = "dark"
    public var accentId: String = "blue"
    /// The colours the "own" annotation palette holds, newest first; empty until one is picked. Read
    /// back with anything that is not a `#RRGGBB` triple dropped and the row cut to twelve, so a
    /// hand-edited file cannot hand the editor a palette it cannot paint.
    public var customPaletteColors: [String] = []

    public init(captureId: String, pasteId: String) {
        self.captureId = captureId
        self.pasteId = pasteId
    }

    public init(
        captureId: String,
        pasteId: String,
        captureEnabled: Bool,
        fullscreenSaveEnabled: Bool,
        fullscreenSaveId: String,
        showNotifications: Bool,
        rememberRegion: Bool,
        captureCursor: Bool,
        saveFormat: String,
        jpegQuality: Int,
        saveDirectory: String,
        language: String,
        autoSaveCaptures: Bool = false,
        playSounds: Bool = true
    ) {
        self.captureId = captureId
        self.pasteId = pasteId
        self.captureEnabled = captureEnabled
        self.fullscreenSaveEnabled = fullscreenSaveEnabled
        self.fullscreenSaveId = fullscreenSaveId
        self.showNotifications = showNotifications
        self.rememberRegion = rememberRegion
        self.captureCursor = captureCursor
        self.saveFormat = saveFormat
        self.jpegQuality = jpegQuality
        self.saveDirectory = saveDirectory
        self.language = language
        self.autoSaveCaptures = autoSaveCaptures
        self.playSounds = playSounds
    }

    /// Port of `Path.Combine(SpecialFolder.MyPictures, "Snapik")`, using the macOS Pictures
    /// directory (falls back to `~/Pictures/Snapik` if unavailable).
    public static func defaultSaveDirectory() -> String {
        let pictures =
            FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Snapik", isDirectory: true).path
    }

    /// Cmd + Option + Shift + S, what "save the whole screen" carries until it is changed. Only the
    /// default moves: a file that already holds an id is read as it was written.
    public static let defaultFullscreenSaveId = "custom:7:83"

    /// How many colours the "own" palette keeps.
    public static let maxCustomPaletteColors = 12

    /// The version every file written by this build carries; see `migrate(_:)`.
    public static let currentSettingsVersion = SettingsMigration.currentVersion

    /// Where "Save package…" writes when nothing of its own has been picked yet. A method and not a
    /// property, because every property of this type is written into `settings.json` and this one is
    /// a fallback, not a preference of its own.
    public func packageDirectory() -> String {
        packageSaveDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? saveDirectory
            : packageSaveDirectory
    }

    // The defaults are the source of every settings object the application builds, so they carry the
    // current version: a file this build wrote is never migrated again.
    public static let `default`: HotkeySettings = {
        var settings = HotkeySettings(captureId: "ctrl-alt-s", pasteId: "ctrl-alt-v")
        settings.settingsVersion = HotkeySettings.currentSettingsVersion
        return settings
    }()

    public static let choices: [HotkeyChoice] = [
        HotkeyChoice(id: "ctrl-alt-s", label: "Ctrl + Alt + S"),
        HotkeyChoice(id: "ctrl-shift-s", label: "Ctrl + Shift + S"),
        HotkeyChoice(id: "alt-s", label: "Alt + S"),
        HotkeyChoice(id: "print-screen", label: "Print Screen"),
        HotkeyChoice(id: "ctrl-alt-v", label: "Ctrl + Alt + V"),
        HotkeyChoice(id: "ctrl-shift-v", label: "Ctrl + Shift + V"),
        HotkeyChoice(id: "alt-v", label: "Alt + V"),
    ]

    public static let pasteChoices: [HotkeyChoice] = choices.filter { $0.id != "print-screen" }

    /// Port of `HotkeySettings.Find(string id)`. Known ids resolve to their fixed label; an
    /// `"custom:{modifiers}:{virtualKey}"` id that `HotkeyRules` lets through reconstructs a
    /// modifier-only label (the key-name portion needs `KeyInterop.KeyFromVirtualKey`, a Win32-only
    /// API, so it falls back to the raw virtual-key code — see CORE-API.md).
    public static func find(_ id: String) -> HotkeyChoice {
        find(id, fallbackId: `default`.captureId)
    }

    /// An id that must not be registered falls back to the default of the shortcut it was read for,
    /// which is why the fallback is an argument (SPEC-DELTA-3 §2.4): the capture, the paste and the
    /// fullscreen save each have a different one, and answering all three with the capture shortcut
    /// would make two of them collide with it.
    public static func find(_ id: String, fallbackId: String) -> HotkeyChoice {
        resolve(id) ?? resolve(fallbackId) ?? choices[0]
    }

    private static func resolve(_ id: String) -> HotkeyChoice? {
        if let preset = choices.first(where: { $0.id == id }) {
            return preset
        }
        // A stored `custom:0:<key>` is nonsense for every key but the two that stand alone, and a
        // stored id that ends with a modifier is nonsense outright; both are answered with the
        // default of their own shortcut. Nothing is written back here, reading never writes; the
        // file itself is put right in `tryRead`.
        guard let parsed = HotkeyRules.parseCustom(id) else { return nil }
        let flags = HotkeyModifiers(rawValue: parsed.modifiers)
        var label = ""
        if flags.contains(.control) { label += "Ctrl + " }
        if flags.contains(.alt) { label += "Alt + " }
        if flags.contains(.shift) { label += "Shift + " }
        if flags.contains(.windows) { label += "Win + " }
        if parsed.virtualKey == 0x13 {
            label += "Pause / Break"
        } else if parsed.virtualKey == 0x2C {
            label += "Print Screen"
        } else {
            label += "VK 0x\(String(parsed.virtualKey, radix: 16, uppercase: true))"
        }
        return HotkeyChoice(id: id, label: label)
    }

    /// Port of `HotkeySettings.Load(string path)`. A read and nothing else: the strip reads the
    /// preferences on every capture, and a read that writes would rewrite `settings.json` with the
    /// keys of this build alone.
    public static func load(path: URL) -> HotkeySettings {
        tryRead(path: path).settings
    }

    /// Port of `HotkeySettings.Migrate`. Brings a file written by an older build up to the current
    /// version. Today it is one rule: the volume that used to be the default becomes the new one,
    /// and anything the user picked is left alone.
    public static func migrate(_ stored: HotkeySettings) -> HotkeySettings {
        guard SettingsMigration.needsMigration(stored.settingsVersion) else { return stored }
        var migrated = stored
        migrated.soundVolume = SettingsMigration.soundVolume(
            storedVersion: stored.settingsVersion, storedVolume: stored.soundVolume)
        migrated.settingsVersion = currentSettingsVersion
        return migrated
    }

    /// Port of `HotkeySettings.LoadAndMigrate`. Reads the file and writes back what the migration
    /// changed, so an older file is brought up to date once instead of on every read. The start of
    /// the application is the only caller: it is the one moment where writing to the settings file
    /// is a deliberate step. A broken id is healed in the file here, and not only in memory, so the
    /// file does not go on holding `custom:0:37` for good while the window shows Ctrl + Alt + S.
    public static func loadAndMigrate(path: URL) -> HotkeySettings {
        let read = tryRead(path: path)
        if read.migrated {
            // A file that cannot be written is still a file that can be read from.
            try? read.settings.save(path: path)
        }
        return read.settings
    }

    // A missing file means "nothing saved yet" and may be overwritten with defaults; a file that
    // exists but does not parse must be left alone, otherwise one bad read wipes every preference.
    private static func tryRead(path: URL) -> (settings: HotkeySettings, migrated: Bool) {
        guard FileManager.default.fileExists(atPath: path.path) else { return (.default, false) }
        guard let data = try? Data(contentsOf: path) else { return (.default, false) }
        // A file truncated to nothing (or to blanks) carries no preferences: it is "nothing saved
        // yet" too.
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (.default, false) }
        guard let stored = try? JSONDecoder().decode(HotkeySettings.self, from: data) else {
            return (.default, false)
        }
        // JSON without the hotkey ids decodes into empty ones, and every `find` over them would fail.
        if stored.captureId.isEmpty || stored.pasteId.isEmpty { return (.default, false) }

        var settings = migrate(stored)
        settings.captureId = find(stored.captureId).id
        settings.pasteId = find(stored.pasteId, fallbackId: `default`.pasteId).id
        settings.fullscreenSaveId = find(
            stored.fullscreenSaveId, fallbackId: defaultFullscreenSaveId
        ).id
        settings.customPaletteColors = keepPaletteColors(stored.customPaletteColors)
        return (settings, settings != stored)
    }

    // A file that holds nothing wrong comes back as the very row it was read with, so a healthy file
    // is not counted as migrated and is not written back.
    private static func keepPaletteColors(_ colours: [String]) -> [String] {
        let kept = colours.filter(isHexColour).prefix(maxCustomPaletteColors)
        return kept.count == colours.count ? colours : Array(kept)
    }

    private static func isHexColour(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }

    /// Port of `HotkeySettings.Save(string path)`.
    public func save(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(self)
        try data.write(to: path, options: .atomic)
    }

    enum CodingKeys: String, CodingKey {
        case captureId = "CaptureId"
        case pasteId = "PasteId"
        case captureEnabled = "CaptureEnabled"
        case fullscreenSaveEnabled = "FullscreenSaveEnabled"
        case fullscreenSaveId = "FullscreenSaveId"
        case showNotifications = "ShowNotifications"
        case rememberRegion = "RememberRegion"
        case captureCursor = "CaptureCursor"
        case saveFormat = "SaveFormat"
        case jpegQuality = "JpegQuality"
        case saveDirectory = "SaveDirectory"
        case language = "Language"
        case autoSaveCaptures = "AutoSaveCaptures"
        case playSounds = "PlaySounds"
        case soundVolume = "SoundVolume"
        case settingsVersion = "SettingsVersion"
        case stackTopmost = "StackTopmost"
        case stackWidth = "StackWidth"
        case stackHeight = "StackHeight"
        case clearStackAfterPaste = "ClearStackAfterPaste"
        case confirmSessionDiscard = "ConfirmSessionDiscard"
        case annotationColor = "AnnotationColor"
        case annotationPalette = "AnnotationPalette"
        case annotationPencil = "AnnotationPencil"
        case annotationThickness = "AnnotationThickness"
        case annotationHighlightThickness = "AnnotationHighlightThickness"
        case annotationFontSize = "AnnotationFontSize"
        case annotationShape = "AnnotationShape"
        case annotationFill = "AnnotationFill"
        case annotationFillColor = "AnnotationFillColor"
        case annotationOutline = "AnnotationOutline"
        case packageSaveDirectory = "PackageSaveDirectory"
        case packageCreateSubfolder = "PackageCreateSubfolder"
        case onboardingVersion = "OnboardingVersion"
        case theme = "Theme"
        case accentId = "AccentId"
        case customPaletteColors = "CustomPaletteColors"
    }

    /// Explicit `init(from:)` (SPEC-DELTA-2B §B, "Риски компиляции" #2): every field is decoded
    /// with `decodeIfPresent`, falling back to its default, so a `settings.json` written before
    /// sync 2 (missing `AutoSaveCaptures`/`PlaySounds`, or any other newer key) still loads instead
    /// of silently failing the whole decode and falling back to `.default` in `load(path:)`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureId = try container.decodeIfPresent(String.self, forKey: .captureId) ?? HotkeySettings.default.captureId
        pasteId = try container.decodeIfPresent(String.self, forKey: .pasteId) ?? HotkeySettings.default.pasteId
        captureEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? true
        fullscreenSaveEnabled = try container.decodeIfPresent(Bool.self, forKey: .fullscreenSaveEnabled) ?? false
        fullscreenSaveId =
            try container.decodeIfPresent(String.self, forKey: .fullscreenSaveId)
            ?? HotkeySettings.defaultFullscreenSaveId
        showNotifications = try container.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? true
        rememberRegion = try container.decodeIfPresent(Bool.self, forKey: .rememberRegion) ?? false
        captureCursor = try container.decodeIfPresent(Bool.self, forKey: .captureCursor) ?? false
        saveFormat = try container.decodeIfPresent(String.self, forKey: .saveFormat) ?? "png"
        jpegQuality = try container.decodeIfPresent(Int.self, forKey: .jpegQuality) ?? 92
        saveDirectory = try container.decodeIfPresent(String.self, forKey: .saveDirectory) ?? HotkeySettings.defaultSaveDirectory()
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "ru"
        autoSaveCaptures = try container.decodeIfPresent(Bool.self, forKey: .autoSaveCaptures) ?? false
        playSounds = try container.decodeIfPresent(Bool.self, forKey: .playSounds) ?? true
        soundVolume =
            try container.decodeIfPresent(Int.self, forKey: .soundVolume) ?? SettingsMigration.defaultSoundVolume
        settingsVersion = try container.decodeIfPresent(Int.self, forKey: .settingsVersion) ?? 0
        stackTopmost = try container.decodeIfPresent(Bool.self, forKey: .stackTopmost) ?? true
        stackWidth =
            try container.decodeIfPresent(Double.self, forKey: .stackWidth) ?? StripResizeGeometry.defaultWidth
        stackHeight =
            try container.decodeIfPresent(Double.self, forKey: .stackHeight) ?? StripResizeGeometry.defaultListHeight
        clearStackAfterPaste =
            try container.decodeIfPresent(Bool.self, forKey: .clearStackAfterPaste) ?? false
        confirmSessionDiscard =
            try container.decodeIfPresent(Bool.self, forKey: .confirmSessionDiscard) ?? true
        annotationColor = try container.decodeIfPresent(String.self, forKey: .annotationColor) ?? "#FF3B30"
        annotationPalette =
            try container.decodeIfPresent(String.self, forKey: .annotationPalette) ?? "standard"
        annotationPencil = try container.decodeIfPresent(String.self, forKey: .annotationPencil) ?? "pen"
        annotationThickness = try container.decodeIfPresent(Double.self, forKey: .annotationThickness) ?? 4
        annotationHighlightThickness =
            try container.decodeIfPresent(Double.self, forKey: .annotationHighlightThickness) ?? 16
        annotationFontSize = try container.decodeIfPresent(Double.self, forKey: .annotationFontSize) ?? 20
        annotationShape = try container.decodeIfPresent(String.self, forKey: .annotationShape) ?? "rectangle"
        annotationFill = try container.decodeIfPresent(String.self, forKey: .annotationFill) ?? "none"
        annotationFillColor = try container.decodeIfPresent(String.self, forKey: .annotationFillColor) ?? ""
        annotationOutline = try container.decodeIfPresent(Bool.self, forKey: .annotationOutline) ?? true
        packageSaveDirectory = try container.decodeIfPresent(String.self, forKey: .packageSaveDirectory) ?? ""
        packageCreateSubfolder =
            try container.decodeIfPresent(Bool.self, forKey: .packageCreateSubfolder) ?? true
        onboardingVersion = try container.decodeIfPresent(Int.self, forKey: .onboardingVersion) ?? 0
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
        accentId = try container.decodeIfPresent(String.self, forKey: .accentId) ?? "blue"
        customPaletteColors = try container.decodeIfPresent([String].self, forKey: .customPaletteColors) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captureId, forKey: .captureId)
        try container.encode(pasteId, forKey: .pasteId)
        try container.encode(captureEnabled, forKey: .captureEnabled)
        try container.encode(fullscreenSaveEnabled, forKey: .fullscreenSaveEnabled)
        try container.encode(fullscreenSaveId, forKey: .fullscreenSaveId)
        try container.encode(showNotifications, forKey: .showNotifications)
        try container.encode(rememberRegion, forKey: .rememberRegion)
        try container.encode(captureCursor, forKey: .captureCursor)
        try container.encode(saveFormat, forKey: .saveFormat)
        try container.encode(jpegQuality, forKey: .jpegQuality)
        try container.encode(saveDirectory, forKey: .saveDirectory)
        try container.encode(language, forKey: .language)
        try container.encode(autoSaveCaptures, forKey: .autoSaveCaptures)
        try container.encode(playSounds, forKey: .playSounds)
        try container.encode(soundVolume, forKey: .soundVolume)
        try container.encode(settingsVersion, forKey: .settingsVersion)
        try container.encode(stackTopmost, forKey: .stackTopmost)
        try container.encode(stackWidth, forKey: .stackWidth)
        try container.encode(stackHeight, forKey: .stackHeight)
        try container.encode(clearStackAfterPaste, forKey: .clearStackAfterPaste)
        try container.encode(confirmSessionDiscard, forKey: .confirmSessionDiscard)
        try container.encode(annotationColor, forKey: .annotationColor)
        try container.encode(annotationPalette, forKey: .annotationPalette)
        try container.encode(annotationPencil, forKey: .annotationPencil)
        try container.encode(annotationThickness, forKey: .annotationThickness)
        try container.encode(annotationHighlightThickness, forKey: .annotationHighlightThickness)
        try container.encode(annotationFontSize, forKey: .annotationFontSize)
        try container.encode(annotationShape, forKey: .annotationShape)
        try container.encode(annotationFill, forKey: .annotationFill)
        try container.encode(annotationFillColor, forKey: .annotationFillColor)
        try container.encode(annotationOutline, forKey: .annotationOutline)
        try container.encode(packageSaveDirectory, forKey: .packageSaveDirectory)
        try container.encode(packageCreateSubfolder, forKey: .packageCreateSubfolder)
        try container.encode(onboardingVersion, forKey: .onboardingVersion)
        try container.encode(theme, forKey: .theme)
        try container.encode(accentId, forKey: .accentId)
        try container.encode(customPaletteColors, forKey: .customPaletteColors)
    }
}
