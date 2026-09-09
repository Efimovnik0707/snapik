// Port of Windows/TransportContracts.cs (TargetProfile, TargetProfiles), SPEC §5.3.
// CONTRACTS.md: "на macOS матчить по bundleIdentifier ИЛИ localizedName (Q2)"; bundle id table
// from CONTRACTS.md "Дефолтные bundle id профилей (Q2, подтвердить на реальной машине)".
//
// Windows `HotkeyGesture` is an arbitrary (modifiers, virtual key) pair; on macOS
// `InputInjecting.injectPaste(alternate:)` only ever sends Cmd+V or Option+V (SPEC §5.6), so the
// gesture collapses to a single `Bool` (`false` = Cmd+V, `true` = Option+V) instead of a separate
// gesture type. This makes the "must never contain Enter" validation structurally unnecessary
// (there is no way to construct an Enter gesture through a `Bool`); the "single package must
// share one gesture" rule remains and is still validated.
//
// Deviation from Windows: the Windows Terminal/VS Code CLI profiles use a *third*, distinct text
// gesture (Ctrl+Shift+V) to avoid triggering the terminal's own paste-and-execute behavior. There
// is no macOS equivalent exposed by `InputInjecting` (only Cmd+V/Option+V exist), so the terminal
// profiles below use Cmd+V for text too, same as the desktop/VS Code profiles. Flagged for CI
// review per the task brief.

import Foundation

/// Port of `PasteTransport`.
public enum PasteTransport: Equatable {
    case singleClipboardPackage
    case stagedSequence
}

/// Port of `ProfileVerification`.
public enum ProfileVerification: Equatable {
    case unverified
    case experimental
    case verified
}

/// Port of `TargetProfile` (`Windows/TransportContracts.cs:43-69`).
public struct TargetProfile: Equatable {
    public let id: String
    public let displayName: String
    public let transport: PasteTransport
    /// `false` = Cmd+V, `true` = Option+V (see file header).
    public let imagePasteIsAlternate: Bool
    /// `false` = Cmd+V, `true` = Option+V (see file header).
    public let textPasteIsAlternate: Bool
    public let allowedBundleIdentifiers: Set<String>
    public let allowedLocalizedNames: Set<String>
    public let acceptanceTimeout: TimeInterval
    public let unobservableSettlementDelay: TimeInterval
    public let verification: ProfileVerification
    public let verifiedVersion: String?
    public let restoreClipboardWhenSafe: Bool

    public init(
        id: String,
        displayName: String,
        transport: PasteTransport,
        imagePasteIsAlternate: Bool,
        textPasteIsAlternate: Bool,
        allowedBundleIdentifiers: Set<String>,
        allowedLocalizedNames: Set<String>,
        acceptanceTimeout: TimeInterval,
        unobservableSettlementDelay: TimeInterval,
        verification: ProfileVerification,
        verifiedVersion: String? = nil,
        restoreClipboardWhenSafe: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.imagePasteIsAlternate = imagePasteIsAlternate
        self.textPasteIsAlternate = textPasteIsAlternate
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
        self.allowedLocalizedNames = allowedLocalizedNames
        self.acceptanceTimeout = acceptanceTimeout
        self.unobservableSettlementDelay = unobservableSettlementDelay
        self.verification = verification
        self.verifiedVersion = verifiedVersion
        self.restoreClipboardWhenSafe = restoreClipboardWhenSafe
    }

    /// Port of `TargetProfile.Validate` (`:56-68`). Messages are the literal Windows English
    /// strings (internal diagnostics, not shown to the end user; SPEC quotes them verbatim).
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty
            || displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            throw TransportError.invalidProfile("A target profile needs an id and display name.")
        }
        if transport == .singleClipboardPackage && imagePasteIsAlternate != textPasteIsAlternate {
            throw TransportError.invalidProfile("A single clipboard package must use one shared paste gesture.")
        }
        if allowedBundleIdentifiers.isEmpty && allowedLocalizedNames.isEmpty {
            throw TransportError.invalidProfile("A target profile needs at least one allowed process name.")
        }
        if acceptanceTimeout <= 0 || unobservableSettlementDelay < 0 {
            throw TransportError.invalidProfile(
                "AcceptanceTimeout must be positive and UnobservableSettlementDelay must be non-negative.")
        }
    }

    /// Port of `WindowsForegroundTargetService.Matches` (`:34-35`), extended per CONTRACTS.md to
    /// also match by `localizedName` (case-insensitive) since bundle identifiers are unconfirmed
    /// (SPEC §10 Q2).
    public func matches(_ target: ForegroundTarget) -> Bool {
        if let bundleIdentifier = target.bundleIdentifier, allowedBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        return allowedLocalizedNames.contains { $0.caseInsensitiveCompare(target.processName) == .orderedSame }
    }
}

/// Bundle identifier / localized name constants from CONTRACTS.md ("Дефолтные bundle id
/// профилей (Q2, подтвердить на реальной машине)"). Unverified; must be confirmed on a real
/// machine (SPEC §10 Q2).
public enum MacTargetBundleIdentifiers {
    public static let codexDesktop = "com.openai.codex"
    public static let chatGPT = "com.openai.chat"
    public static let claudeDesktop = "com.anthropic.claudefordesktop"
    public static let terminal = "com.apple.Terminal"
    public static let iTerm2 = "com.googlecode.iterm2"
    public static let visualStudioCode = "com.microsoft.VSCode"
    public static let cursor = "com.todesktop.230313mzl4w4u92"
}

/// Port of `TargetProfiles` (`Windows/TransportContracts.cs:71-147`), SPEC §5.3 table, adapted to
/// the macOS candidates CONTRACTS.md lists (Codex/ChatGPT desktop, Claude desktop, Terminal,
/// iTerm2, VS Code). All Unverified, 8s acceptance timeout, 900ms unobservable settlement delay,
/// matching the Windows built-ins exactly (`Windows/TransportContracts.cs:73-74`).
public enum BuiltInTargetProfiles {
    private static let defaultTimeout: TimeInterval = 8
    private static let defaultDelay: TimeInterval = 0.9

    public static let claudeCodeTerminal = TargetProfile(
        id: "claude-code-terminal",
        displayName: "Claude Code · Terminal (не проверено)",
        transport: .stagedSequence,
        imagePasteIsAlternate: true,
        textPasteIsAlternate: false,
        allowedBundleIdentifiers: [MacTargetBundleIdentifiers.terminal, MacTargetBundleIdentifiers.iTerm2],
        allowedLocalizedNames: ["Terminal", "iTerm2"],
        acceptanceTimeout: defaultTimeout,
        unobservableSettlementDelay: defaultDelay,
        verification: .unverified)

    public static let claudeCodeVisualStudioCode = TargetProfile(
        id: "claude-code-vscode",
        displayName: "Claude Code · Visual Studio Code (не проверено)",
        transport: .stagedSequence,
        imagePasteIsAlternate: true,
        textPasteIsAlternate: false,
        allowedBundleIdentifiers: [MacTargetBundleIdentifiers.visualStudioCode],
        allowedLocalizedNames: ["Code"],
        acceptanceTimeout: defaultTimeout,
        unobservableSettlementDelay: defaultDelay,
        verification: .unverified)

    public static let claudeDesktop = TargetProfile(
        id: "claude-desktop",
        displayName: "Claude Desktop (не проверено)",
        transport: .stagedSequence,
        imagePasteIsAlternate: false,
        textPasteIsAlternate: false,
        allowedBundleIdentifiers: [MacTargetBundleIdentifiers.claudeDesktop],
        allowedLocalizedNames: ["Claude"],
        acceptanceTimeout: defaultTimeout,
        unobservableSettlementDelay: defaultDelay,
        verification: .unverified)

    public static let codexDesktop = TargetProfile(
        id: "codex-desktop",
        displayName: "Codex Desktop (не проверено)",
        transport: .stagedSequence,
        imagePasteIsAlternate: false,
        textPasteIsAlternate: false,
        allowedBundleIdentifiers: [MacTargetBundleIdentifiers.codexDesktop, MacTargetBundleIdentifiers.chatGPT],
        allowedLocalizedNames: ["Codex", "ChatGPT"],
        acceptanceTimeout: defaultTimeout,
        unobservableSettlementDelay: defaultDelay,
        verification: .unverified)

    public static let codexTerminal = TargetProfile(
        id: "codex-terminal",
        displayName: "Codex CLI · Terminal (не проверено)",
        transport: .stagedSequence,
        imagePasteIsAlternate: false,
        textPasteIsAlternate: false,
        allowedBundleIdentifiers: [MacTargetBundleIdentifiers.terminal, MacTargetBundleIdentifiers.iTerm2],
        allowedLocalizedNames: ["Terminal", "iTerm2"],
        acceptanceTimeout: defaultTimeout,
        unobservableSettlementDelay: defaultDelay,
        verification: .unverified)

    public static let codexVisualStudioCode = TargetProfile(
        id: "codex-vscode",
        displayName: "Codex CLI · Visual Studio Code (не проверено)",
        transport: .stagedSequence,
        imagePasteIsAlternate: false,
        textPasteIsAlternate: false,
        allowedBundleIdentifiers: [MacTargetBundleIdentifiers.visualStudioCode],
        allowedLocalizedNames: ["Code"],
        acceptanceTimeout: defaultTimeout,
        unobservableSettlementDelay: defaultDelay,
        verification: .unverified)

    /// Port of `TargetProfiles.All` (`:142-143`). Order matters: `EdgeStackWindow.xaml.cs:74`
    /// defaults to the fourth element (`codexDesktop`).
    public static let all: [TargetProfile] = [
        claudeCodeTerminal, claudeCodeVisualStudioCode, claudeDesktop, codexDesktop, codexTerminal,
        codexVisualStudioCode,
    ]

    /// Port of the default selection at `EdgeStackWindow.xaml.cs:74` (fourth element = Codex Desktop).
    public static let `default` = codexDesktop
}
