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
    public var fullscreenSaveId: String = "custom:4:44"
    public var showNotifications: Bool = true
    public var rememberRegion: Bool = false
    public var captureCursor: Bool = false
    public var saveFormat: String = "png"
    public var jpegQuality: Int = 90
    public var saveDirectory: String = HotkeySettings.defaultSaveDirectory()
    public var language: String = "ru"
    /// Port of `AutoSaveCaptures` (SPEC-DELTA-2B §B/§E4), default `false`.
    public var autoSaveCaptures: Bool = false
    /// Port of `PlaySounds` (SPEC-DELTA-2B §B/§E2), default `true`.
    public var playSounds: Bool = true

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

    public static let `default` = HotkeySettings(captureId: "ctrl-alt-s", pasteId: "ctrl-alt-v")

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

    /// Port of `HotkeySettings.Find(string id)`. Known ids resolve to their fixed label; unknown
    /// `"custom:{modifiers}:{virtualKey}"` ids reconstruct a modifier-only label (the key-name
    /// portion needs `KeyInterop.KeyFromVirtualKey`, a Win32-only API, so it falls back to the
    /// raw virtual-key code — see CORE-API.md). Anything else falls back to `choices[0]`, matching
    /// the C# fallback.
    public static func find(_ id: String) -> HotkeyChoice {
        if let preset = choices.first(where: { $0.id == id }) {
            return preset
        }

        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == "custom",
            let modifiersValue = UInt32(parts[1]), let keyValue = UInt32(parts[2]),
            keyValue > 0, keyValue < 255, (modifiersValue & ~UInt32(15)) == 0
        {
            let flags = HotkeyModifiers(rawValue: modifiersValue)
            var label = ""
            if flags.contains(.control) { label += "Ctrl + " }
            if flags.contains(.alt) { label += "Alt + " }
            if flags.contains(.shift) { label += "Shift + " }
            if flags.contains(.windows) { label += "Win + " }
            if keyValue == 0x13 {
                label += "Pause / Break"
            } else if keyValue == 0x2C {
                label += "Print Screen"
            } else {
                label += "VK 0x\(String(keyValue, radix: 16, uppercase: true))"
            }
            return HotkeyChoice(id: id, label: label)
        }

        return choices[0]
    }

    /// Port of `HotkeySettings.Load(string path)`.
    public static func load(path: URL) -> HotkeySettings {
        guard FileManager.default.fileExists(atPath: path.path) else { return .default }
        guard let data = try? Data(contentsOf: path) else { return .default }
        guard let settings = try? JSONDecoder().decode(HotkeySettings.self, from: data) else { return .default }
        return settings
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
        fullscreenSaveId = try container.decodeIfPresent(String.self, forKey: .fullscreenSaveId) ?? "custom:4:44"
        showNotifications = try container.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? true
        rememberRegion = try container.decodeIfPresent(Bool.self, forKey: .rememberRegion) ?? false
        captureCursor = try container.decodeIfPresent(Bool.self, forKey: .captureCursor) ?? false
        saveFormat = try container.decodeIfPresent(String.self, forKey: .saveFormat) ?? "png"
        jpegQuality = try container.decodeIfPresent(Int.self, forKey: .jpegQuality) ?? 90
        saveDirectory = try container.decodeIfPresent(String.self, forKey: .saveDirectory) ?? HotkeySettings.defaultSaveDirectory()
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "ru"
        autoSaveCaptures = try container.decodeIfPresent(Bool.self, forKey: .autoSaveCaptures) ?? false
        playSounds = try container.decodeIfPresent(Bool.self, forKey: .playSounds) ?? true
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
    }
}
