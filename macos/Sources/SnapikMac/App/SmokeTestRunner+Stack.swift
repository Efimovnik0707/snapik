// Smoke probes of the strip (SPEC §8.4, SPEC-DELTA-3 §7 wave 1 portion A). They live in a file of
// their own because `SmokeTestRunner.swift` is folded together in wave 2: this extension publishes
// one entry point, `stackProbes(options:)`, and the runner will call it there.
import AppKit
import SnapikCore

@MainActor
extension SmokeTestRunner {
    /// Every check of the strip, as `(name, passed)` pairs in the order they were run. Nothing here
    /// touches the screen, the session on disk or the clipboard: the window is built, laid out and
    /// measured, and the two modes it has are switched by hand. `options` wants a `--data-dir` of its
    /// own, the way the editor probe has one, so the coordinator built here cannot meet the session
    /// of another step.
    static func stackProbes(options: CommandLineOptions) -> [(String, Bool)] {
        var checks: [(String, Bool)] = []

        // [ТЗ№4 C4, C6] The chain of the round: 244 − 2·20 − 2·10 − 2·8 = 168, the numbers of
        // `reference-png/04`. The card is the last link of it, and the round is drawn on that figure.
        let width = CGFloat(StripResizeGeometry.defaultWidth)
        checks.append(
            (
                "strip geometry chain 244 → 204 → 168",
                width == 244 && StackMetrics.panelWidth(windowWidth: width) == 204
                    && StackMetrics.cardWidth(windowWidth: width) == 168
            ))

        // A width stored by an older version (208 was the number of Windows 1.4.0) is lifted to the
        // floor of this round instead of opening a strip narrower than its own card.
        checks.append(
            (
                "a stored width below the floor is lifted",
                StripResizeGeometry.clampWidth(208, workWidth: 1920) == StripResizeGeometry.minimumWidth
                    && StripResizeGeometry.clampWidth(400, workWidth: 1920) == 400
            ))

        let coordinator = AppCoordinator(options: options)
        let controller = EdgeStackWindowController(coordinator: coordinator)
        let content = controller.contentContainer
        content.frame = NSRect(x: 0, y: 0, width: width, height: content.windowHeight())
        content.layoutSubtreeIfNeeded()

        // [ТЗ№4 C3] The empty strip is as tall as its content: the header, the hint and the button.
        checks.append(
            (
                "an empty strip is as tall as its hint",
                content.isEmpty && content.windowHeight() == content.chromeHeight() + StackMetrics.emptyHintHeight
            ))

        // [ТЗ№4 C1] The cards are in the order of the data, the newest over the oldest: the last card
        // is the last subview (drawn last) and it sits lowest on the screen, overlapping the one
        // before it by `cardOverlap`.
        // The three kinds stand next to each other on purpose: the two that carry a chip are on the
        // screen when the English sweep below is taken.
        let kinds: [CaptureKind] = [.region, .fullscreen, .import, .region]
        let rows = (0..<4).map { index in
            StackCaptureRow(
                id: SBGuid(), label: (try? CaptureLabels.forIndex(index)) ?? "?", thumbnail: nil, noteCount: index,
                isSent: false, kind: kinds[index])
        }
        content.reload(rows: rows)
        content.listHeight = CGFloat(StripResizeGeometry.defaultListHeight)
        content.frame = NSRect(x: 0, y: 0, width: width, height: content.windowHeight())
        content.layoutSubtreeIfNeeded()

        let cards = content.cardViews
        let frames = cards.map(\.frame)
        let descending = zip(frames, frames.dropFirst()).allSatisfy { $0.maxY > $1.maxY }
        let stepped = zip(frames, frames.dropFirst()).allSatisfy { abs($0.maxY - $1.maxY - StackMetrics.cardStep) < 0.5 }
        // The newest capture is the last subview, which is the one drawn over all the others: that is
        // the whole of the depth this round has, in place of the ZIndex converter of Windows.
        let newestLast = cards.last === cards.last?.superview?.subviews.last
        checks.append(("the cards keep the order of the data", cards.count == 4 && descending && stepped && newestLast))
        checks.append(
            (
                "the card is 168 wide and throws its shadow upwards",
                frames.allSatisfy { abs($0.width - StackMetrics.cardWidth(windowWidth: width)) < 0.5 }
                    && cards.allSatisfy { ($0.layer?.shadowOffset.height ?? 0) > 0 }
            ))

        // S-2: every way of adding a capture asks the strip first, and the strip answers from the
        // constant both builds share.
        checks.append(
            (
                "the strip stops at twenty-six",
                !controller.stripIsFull(adding: SentCaptureRules.maxStripCaptures)
                    && controller.stripIsFull(adding: SentCaptureRules.maxStripCaptures + 1)
            ))

        // §1.20: the strip in English shows no Russian left behind.
        content.applyLocalization(language: "en")
        content.setEmptyHintShortcut(nil)
        let cyrillic = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        let untranslated = content.smokeVisibleStrings().filter { $0.rangeOfCharacter(from: cyrillic) != nil }
        checks.append(("the strip translates into English", untranslated.isEmpty))
        content.applyLocalization(language: coordinator.language)

        // S-10: the capsule is a mode of the same window, at the same right edge, and the strip comes
        // back to the width it was collapsed at.
        if let window = controller.window {
            // The working area of the machine the probe runs on, and not a desk-sized rectangle: the
            // capsule is placed by `positionAtEdge`, which asks the screen, and a CI runner answers
            // with a screen of its own size.
            let work = controller.workArea()
            window.setFrame(
                NSRect(
                    x: work.maxX - width, y: work.minY + 20, width: width, height: content.windowHeight()),
                display: false)
            let rightEdge = window.frame.maxX
            let topEdge = window.frame.maxY
            controller.collapseToCapsule()
            let capsuleKeepsTheEdge = window.frame.height <= StackMetrics.capsuleHeight + StackMetrics.shadowMargin * 2
            controller.expandFromCapsule()
            let cameBack =
                capsuleKeepsTheEdge && abs(window.frame.width - width) < 0.5
                && abs(window.frame.maxY - topEdge) < 0.5 && abs(window.frame.maxX - rightEdge) < 0.5
            checks.append(
                (
                    "the capsule collapses and opens at the same corner"
                        + (cameBack
                            ? ""
                            : ": corner \(topEdge)×\(rightEdge) came back as "
                                + "\(window.frame.maxY)×\(window.frame.maxX), width \(window.frame.width)"),
                    cameBack
                ))
        }

        // [ТЗ№4 C7] The strip hides from our own capture only, and comes back straight after it.
        let defaultSharing = WindowCaptureExclusion.sharingType
        WindowCaptureExclusion.beginOwnCapture()
        let duringCapture = WindowCaptureExclusion.sharingType
        WindowCaptureExclusion.endOwnCapture()
        checks.append(
            (
                "the strip hides from our own capture only",
                defaultSharing == .readOnly && WindowCaptureExclusion.sharingType == .readOnly
                    // `--demo-screenshot` switches the whole mechanism off before any window exists.
                    && (!WindowCaptureExclusion.isEnabled || duringCapture == .none)
            ))

        controller.hide()
        return checks
    }
}
