// Port of the workspace half of `SessionWorkspace`, SPEC §1.2, §3.4. Public contract: CONTRACTS.md "Editor".
import Foundation
import SnapBriefCore

/// Everything the overlay editor needs from the owning session, without depending on the shell's
/// `AppCoordinator`/`SessionWorkspace` types directly (those live in `Sources/SnapBriefMac/App`,
/// outside this zone). `nextCaptureIndex` is the zero-based index this new capture will occupy
/// once committed, used for `CaptureLabels.forIndex` (SPEC §2.4/§1.3 "СНИМОК {метка}").
struct EditorWorkspaceContext {
    let session: SnapBriefSession
    let sessionDirectory: URL
    let assetStore: SessionAssetStore
    let nextCaptureIndex: Int
}
