// Port of `DiscardSessionWindow.xaml(.cs)`, SPEC-DELTA-3 §1.3 S-13.
import AppKit
import SnapikCore

/// Clearing the strip and leaving the application delete the captures of the session from the disk,
/// so both ask first. An empty strip has nothing to lose and never asks, and the question carries
/// the box that turns it off; the automatic "clear after pasting" is not a decision of the user and
/// stays silent.
///
/// `NSAlert.suppressionButton` is the box: AppKit draws and lays it out, which is the whole of the
/// Windows window that is not the two strings.
@MainActor
enum DiscardSessionSheet {
    struct Answer {
        let confirmed: Bool
        let doNotAskAgain: Bool
    }

    static func ask(language: String) -> Answer {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MacUiText.text("Удалить снимки сессии?", language: language)
        alert.informativeText = MacUiText.text(
            "Снимки этой сессии будут удалены. Чтобы сохранить, нажмите «Сохранить пакет…» в меню •••",
            language: language)
        // Deleting is what "Clear the strip" and the exit were asked for, so it is the default
        // button; Esc and the cancel button leave the captures where they are.
        alert.addButton(withTitle: MacUiText.text("Удалить", language: language))
        alert.addButton(withTitle: MacUiText.text("Отмена", language: language))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = MacUiText.text("Больше не спрашивать", language: language)

        let confirmed = alert.runModal() == .alertFirstButtonReturn
        // The box is read only after "Удалить": a question that was cancelled decides nothing.
        return Answer(confirmed: confirmed, doNotAskAgain: confirmed && alert.suppressionButton?.state == .on)
    }
}
