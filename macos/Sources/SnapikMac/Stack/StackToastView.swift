// Port of the toast of the strip (`EdgeStackWindow.xaml:322-329`, `ShowToast`/`HideToastNow`,
// `EdgeStackWindow.xaml.cs:1619-1670`), SPEC-DELTA-3 §1.3 S-12.
import AppKit

/// One toast at a time: a confirmation that fades in over the footer of the strip, carries at most
/// one action ("Отменить" after a delete) and never takes focus. A toast shown while the previous
/// one is still fading keeps a generation of its own, so the late fade-out of the older message
/// cannot hide the newer one.
final class StackToastView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton()
    private var action: (() -> Void)?
    private var generation = 0
    private var hideWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        alphaValue = 0
        isHidden = true

        label.font = NSFont.systemFont(ofSize: 11)
        label.maximumNumberOfLines = 3
        addSubview(label)

        actionButton.isBordered = false
        actionButton.font = NSFont.systemFont(ofSize: 11)
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        actionButton.isHidden = true
        addSubview(actionButton)

        applyPalette()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette() {
        layer?.backgroundColor = StackTheme.palette.elevated.cgColor
        label.textColor = StackTheme.palette.text
        actionButton.contentTintColor = StackTheme.accent.text
    }

    /// The height this toast asks for at `width`, its padding included.
    func preferredHeight(width: CGFloat) -> CGFloat {
        guard !isHidden else { return 0 }
        let textWidth = max(40, width - 16 - (actionButton.isHidden ? 0 : actionWidth() + 8))
        return max(26, StackTextMeasure.height(of: label, width: textWidth) + 10)
    }

    override func layout() {
        super.layout()
        let actionW = actionButton.isHidden ? 0 : actionWidth()
        actionButton.frame = NSRect(x: bounds.width - 8 - actionW, y: 0, width: actionW, height: bounds.height)
        let textWidth = max(0, bounds.width - 16 - (actionButton.isHidden ? 0 : actionW + 8))
        label.frame = NSRect(x: 8, y: 5, width: textWidth, height: max(0, bounds.height - 10))
    }

    private func actionWidth() -> CGFloat {
        max(40, actionButton.attributedTitle.size().width + 4)
    }

    /// Shows `text` for `StackMetrics.toastLifetimeSeconds`, replacing whatever is on screen.
    func show(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil, onLayoutChange: @escaping () -> Void) {
        hideWorkItem?.cancel()
        generation += 1
        let current = generation
        self.action = action
        label.stringValue = text
        if let actionTitle, action != nil {
            actionButton.attributedTitle = NSAttributedString(
                string: actionTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: StackTheme.accent.text,
                ])
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
        isHidden = false
        onLayoutChange()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = StackMetrics.toastFadeSeconds
            animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.fadeOut(generation: current, onLayoutChange: onLayoutChange)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + StackMetrics.toastLifetimeSeconds, execute: work)
    }

    /// A toast that outlives the panel it belongs to would greet the next showing with stale text,
    /// so hiding the strip takes the toast with it instead of waiting for the timer.
    func hideNow(onLayoutChange: () -> Void) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        generation += 1
        action = nil
        alphaValue = 0
        isHidden = true
        onLayoutChange()
    }

    private func fadeOut(generation current: Int, onLayoutChange: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = StackMetrics.toastFadeSeconds
                animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                guard let self, self.generation == current else { return }
                self.isHidden = true
                self.action = nil
                onLayoutChange()
            })
    }

    @objc private func actionClicked() {
        let pending = action
        hideWorkItem?.cancel()
        generation += 1
        action = nil
        alphaValue = 0
        isHidden = true
        pending?()
    }
}
