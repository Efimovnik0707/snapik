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

        // §5 point 2: a card born while the strip is already in English arrives translated — the
        // chip of the kind is written by the card, from the language the strip is showing.
        content.reload(rows: rows)
        let chipsOfNewCards = content.cardViews.flatMap { $0.smokeVisibleStrings() }
        checks.append(
            (
                "a card born in an English strip carries a translated chip",
                chipsOfNewCards == ["screen", "import"]
            ))
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

        checks += growthProbes(controller: controller)
        checks += kindProbes(options: options)

        controller.hide()
        return checks
    }

    /// Port of `RunStripGrowthProbe`/`ProbeStrip` (`src/Snapik.App/EdgeStackWindow.xaml.cs:2129-2233`),
    /// SPEC-DELTA-5 §4.2: how tall the list is for what it holds, whether it scrolls, where it
    /// stands after a capture, and that a card opened by the pointer grows the document and not the
    /// strip. Every case is laid out on the same content view the window carries, the way the capsule
    /// probe above drives it: `reload(rows:)` builds the cards, `applyListHeight()` settles the
    /// height the way every real change of the strip does, and `layoutSubtreeIfNeeded()` is what
    /// works the frames out.
    private static func growthProbes(controller: EdgeStackWindowController) -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        let content = controller.contentContainer
        let width = CGFloat(StripResizeGeometry.defaultWidth)

        func layOut(cards count: Int) {
            content.reload(rows: rowsOfProbeCaptures(count: count))
            controller.applyListHeight()
            content.frame = NSRect(x: 0, y: 0, width: width, height: content.windowHeight())
            content.layoutSubtreeIfNeeded()
        }

        // Five cards: 14 + 4·30 + 78 + 8 = 220, and nothing to scroll.
        layOut(cards: 5)
        let fiveFits = content.smokeDocumentHeight <= content.smokeVisibleListHeight + 0.5
        checks.append(
            (
                "five cards take 220 and do not scroll"
                    + (content.listHeight == 220 && fiveFits ? "" : ": \(content.listHeight), document \(content.smokeDocumentHeight) of \(content.smokeVisibleListHeight)"),
                content.listHeight == 220 && fiveFits
            ))

        // The last card is whole: the bottom of it stands on the bottom padding of the list and not
        // below the edge of what is seen (`TheLastCardIsWhole`).
        let lastCardIsWhole = (content.cardViews.last?.frame.minY ?? -1) >= StackMetrics.listPaddingBottom - 0.5
        checks.append(("the bottom of the last card is whole", lastCardIsWhole))

        // A card opened by the pointer shows its full height and pushes the ones below it down: the
        // list keeps its 220 and only the document grows, by exactly one overlap. The card that
        // opened does not move — in this container that is its distance from the top of the document,
        // because the document itself has grown under it.
        let documentBefore = content.smokeDocumentHeight
        let openedCard = content.cardViews.count > 2 ? content.cardViews[2] : nil
        let topBefore = openedCard.map { documentBefore - $0.frame.maxY }
        openedCard?.isUnfolded = true
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        let topAfter = openedCard.map { content.smokeDocumentHeight - $0.frame.maxY }
        checks.append(
            (
                "an opened card grows the document and not the strip",
                openedCard != nil && content.listHeight == 220
                    && abs(content.smokeDocumentHeight - documentBefore - StackMetrics.cardOverlap) < 0.5
                    && abs((topAfter ?? -1) - (topBefore ?? -2)) < 0.5
            ))
        openedCard?.isUnfolded = false

        // Twelve cards ask for 430 and are stopped by the ceiling of the stored height: the list is
        // 372 and what is left is scrolled.
        layOut(cards: 12)
        let twelveScroll = content.smokeDocumentHeight > content.smokeVisibleListHeight + 0.5
        checks.append(
            (
                "twelve cards stop at the ceiling of 372 and scroll"
                    + (content.listHeight == 372 && twelveScroll ? "" : ": \(content.listHeight), document \(content.smokeDocumentHeight) of \(content.smokeVisibleListHeight)"),
                content.listHeight == 372 && twelveScroll
            ))

        // A showing of the strip ends at the capture that came last. Zero is the bottom of the
        // document here (SPEC-DELTA-5 §2.11), and the list starts at the other end of it.
        let originBeforePin = content.smokeScrollOrigin
        content.scrollToNewest()
        content.layoutSubtreeIfNeeded()
        checks.append(
            (
                "the strip shows the newest capture",
                originBeforePin > 0.5 && abs(content.smokeScrollOrigin) < 0.5
            ))

        // A height dragged by hand is the height of the list, empty space under the last card
        // included (SPEC-DELTA-5 §1.2 L-12). The pure part is a unit test of Core; what is asked
        // here is that the window is as tall as that number plus its chrome.
        let manual = StripResizeGeometry.listHeight(count: 3, stored: 310, manual: true)
        layOut(cards: 3)
        content.listHeight = CGFloat(manual)
        content.frame = NSRect(x: 0, y: 0, width: width, height: content.windowHeight())
        content.layoutSubtreeIfNeeded()
        checks.append(
            (
                "a height dragged by hand stays",
                manual == 310 && abs(content.windowHeight() - content.chromeHeight() - 310) < 0.5
            ))

        content.reload(rows: [])
        return checks
    }

    /// `count` cards of the strip, lettered as the strip letters them.
    private static func rowsOfProbeCaptures(count: Int) -> [StackCaptureRow] {
        (0..<count).map { index in
            StackCaptureRow(
                id: SBGuid(), label: (try? CaptureLabels.forIndex(index)) ?? "?", thumbnail: nil,
                noteCount: 0, isSent: false, kind: .region)
        }
    }

    /// A-1 and A-2 (`SmokeTestRunner.cs:1293-1329`): the two captures that are not a region say so
    /// themselves. Both are checked without the strip on the screen — what is asked is the way the
    /// kind and the title of a capture reach `prompt.md` and the session file.
    private static func kindProbes(options: CommandLineOptions) -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        let start = Date(timeIntervalSince1970: 1_760_000_000)

        // A-1: a whole-screen capture names itself even though nobody wrote a word about it, and the
        // kind and the number of monitors it covered survive the file.
        var fullscreen = CaptureItem.create(
            sourceImagePath: "source/screen.png", pixelWidth: 3840, pixelHeight: 1125)
        fullscreen.kind = .fullscreen
        fullscreen.monitorCount = 2
        var namesItself = false
        var survivesTheFile = false
        do {
            let session = try SessionOperations.addCapture(
                SnapikSession.create(nowUtc: start), capture: fullscreen, nowUtc: start)
            namesItself = try PromptGenerator().generate(session) == "Снимок A — весь экран."
            let restored = try SnapikJson.decoder.decode(
                SnapikSession.self, from: SnapikJson.encoder.encode(session))
            survivesTheFile =
                restored.captures.first?.kind == .fullscreen && restored.captures.first?.monitorCount == 2
        } catch {
            // Both answers stay `false`: a probe that could not be run has not passed.
        }
        checks.append(("a whole-screen capture names itself", namesItself))
        checks.append(("the kind of a capture and its monitors survive the session file", survivesTheFile))

        // [ТЗ№4 E-7] The seam between the strip and the editor: reopening a card and finishing it
        // must not quietly turn it back into a region. The two calls asked here are the two the
        // editor makes — `EditorCapture.fromCore` is what `presentExisting` opens the card with, and
        // `toCore()` is what `commit` hands to the delegate — and the answer is read back off the
        // session file, the place the loss would have shown.
        var survivesTheEditor = false
        if let probeImage = makeSolidImage(width: 64, height: 48) {
            var reopened = fullscreen
            reopened.title = "Экран.png"
            let committed = EditorCapture.fromCore(reopened, image: probeImage).toCore()
            do {
                let session = try SessionOperations.addCapture(
                    SnapikSession.create(nowUtc: start), capture: committed, nowUtc: start)
                let restored = try SnapikJson.decoder.decode(
                    SnapikSession.self, from: SnapikJson.encoder.encode(session)).captures.first
                survivesTheEditor =
                    restored?.kind == .fullscreen && restored?.monitorCount == 2
                    && restored?.title == "Экран.png"
            } catch {
                // A probe that could not be run has not passed.
            }
        }
        checks.append(("a reopened capture keeps its kind and its name through the editor", survivesTheEditor))

        // A-2: the import of a file from disk, the whole way — a real PNG, the decoder, and the name
        // of the file, which is what tells one import from another in `prompt.md` and on the card.
        let probeRoot = (options.dataDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("import-probe", isDirectory: true)
        var reachesTheStrip = false
        do {
            try FileManager.default.createDirectory(at: probeRoot, withIntermediateDirectories: true)
            let path = probeRoot.appendingPathComponent("IMG_0512.png")
            guard let drawn = makeSolidImage(width: 160, height: 120), let png = ImageCodec.encode(drawn, format: .png)
            else { throw SnapikError.invalidData("the probe image could not be encoded") }
            try ImageCodec.writeAtomically(png, to: path)

            guard let loaded = ImageCodec.loadImage(at: path) else {
                throw SnapikError.invalidData("the probe image could not be read back")
            }
            var imported = CaptureItem.create(
                sourceImagePath: "source/import.png", pixelWidth: loaded.width, pixelHeight: loaded.height,
                title: path.lastPathComponent)
            imported.kind = .import
            let session = try SessionOperations.addCapture(
                SnapikSession.create(nowUtc: start), capture: imported, nowUtc: start)
            let prompt = try PromptGenerator().generate(session)
            reachesTheStrip = loaded.width == 160 && loaded.height == 120 && prompt == "Снимок A — IMG_0512.png."
        } catch {
            reachesTheStrip = false
        }
        checks.append(("a file from disk reaches the strip under its own name", reachesTheStrip))

        return checks
    }

    private static func makeSolidImage(width: Int, height: Int) -> CGImage? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
        else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
