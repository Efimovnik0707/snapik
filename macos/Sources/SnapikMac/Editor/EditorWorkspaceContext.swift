// Port of the workspace half of `SessionWorkspace`, SPEC §1.2, §3.4. Public contract: CONTRACTS.md "Editor".
import Foundation
import SnapikCore

/// Everything the overlay editor needs from the owning session, without depending on the shell's
/// `AppCoordinator`/`SessionWorkspace` types directly (those live in `Sources/SnapikMac/App`,
/// outside this zone). `nextCaptureIndex` is the zero-based index this new capture will occupy
/// once committed, used for `CaptureLabels.forIndex` (SPEC §2.4/§1.3 "СНИМОК {метка}").
struct EditorWorkspaceContext {
    let session: SnapikSession
    let sessionDirectory: URL
    let assetStore: SessionAssetStore
    let nextCaptureIndex: Int
    /// Where "remember last region" persists its state (SPEC §1.16), owned by the shell's
    /// `SessionWorkspace.regionPath` (`Sources/SnapikMac/App`, outside this zone) and passed in
    /// here rather than re-derived, since this zone has no view onto the shell's app-support layout.
    let regionPath: URL

    /// Where the panel writes what the next capture starts with (SPEC-DELTA-3 §1.4 E-16,
    /// `SaveAppearanceDefaults`). Derived from `regionPath` rather than carried as a field of its
    /// own: `SessionWorkspace` puts `last-region.json` beside `settings.json`, in the one directory
    /// both of them live in, and the shell that builds this context is outside this zone.
    var settingsPath: URL {
        regionPath.deletingLastPathComponent().appendingPathComponent("settings.json")
    }
}
