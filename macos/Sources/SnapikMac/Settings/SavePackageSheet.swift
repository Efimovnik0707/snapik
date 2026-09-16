// Port of `src/Snapik.App/SavePackageWindow.xaml(.cs)`, SPEC-DELTA-3 §1.5 G-12.
import AppKit
import SnapikCore

/// Where the package goes and under which name; the folder name is used only with a subfolder.
struct SavePackageChoice: Equatable {
    let directory: String
    let createSubfolder: Bool
    let folderName: String
}

/// One window instead of the system folder picker: saving the same package twice into the same
/// folder is the common case, so the folder, the name and the subfolder switch are all on screen at
/// once and the choice is remembered.
///
/// Not themed: the window is on screen for seconds and its colours are written down, exactly as the
/// Windows one is (`SavePackageWindow.xaml:1-3`).
@MainActor
final class SavePackageSheetController: NSWindowController, NSWindowDelegate {
    /// What the caller gets when the window is closed with "Сохранить"; nil on every other way out.
    private(set) var result: SavePackageChoice?
    /// Called once the window has closed, with the choice or with nil.
    var onClosed: ((SavePackageChoice?) -> Void)?

    private let language: String
    private let titleLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let directoryField = NSTextField(frame: .zero)
    private let browseButton = NSButton(title: "", target: nil, action: nil)
    private let subfolderBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let nameLabel = NSTextField(labelWithString: "")
    private let nameField = NSTextField(frame: .zero)
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let letterLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)

    init(settings: HotkeySettings, now: Date) {
        self.language = settings.language
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Snapik"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(hex: "#171B22")
        super.init(window: window)
        window.delegate = self

        directoryField.stringValue = settings.packageDirectory()
        subfolderBox.state = settings.packageCreateSubfolder ? .on : .off
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        nameField.stringValue = "Snapik-\(stamp.string(from: now))"

        buildContent(in: window)
        applyLocalization()
        updateNameState()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = NSColor(hex: "#EEF2F8")
        for label in [directoryLabel, nameLabel] {
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = NSColor(hex: "#EEF2F8")
        }
        for label in [hintLabel, letterLabel] {
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = NSColor(hex: "#9AA6B6")
        }
        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = NSColor(hex: "#FF9B95")
        errorLabel.isHidden = true
        subfolderBox.contentTintColor = NSColor(hex: "#EEF2F8")
        subfolderBox.target = self
        subfolderBox.action = #selector(subfolderChanged)
        browseButton.target = self
        browseButton.action = #selector(browseClicked)
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.keyEquivalent = "\r"

        for view in [
            titleLabel, directoryLabel, directoryField, browseButton, subfolderBox, nameLabel, nameField,
            hintLabel, letterLabel, errorLabel, cancelButton, saveButton,
        ] as [NSView] {
            contentView.addSubview(view)
        }
        layoutContent(in: contentView)
    }

    private func layoutContent(in contentView: NSView) {
        let padding: CGFloat = 24
        let width = contentView.bounds.width - padding * 2
        var y = contentView.bounds.height - padding - 30
        titleLabel.frame = NSRect(x: padding, y: y, width: width, height: 30)
        y -= 28
        directoryLabel.frame = NSRect(x: padding, y: y, width: width, height: 18)
        y -= 32
        directoryField.frame = NSRect(x: padding, y: y, width: width - 96, height: 26)
        browseButton.frame = NSRect(x: padding + width - 90, y: y, width: 90, height: 26)
        y -= 34
        subfolderBox.frame = NSRect(x: padding, y: y, width: width, height: 20)
        y -= 32
        nameLabel.frame = NSRect(x: padding, y: y, width: width, height: 18)
        y -= 32
        nameField.frame = NSRect(x: padding, y: y, width: width, height: 26)
        y -= 40
        hintLabel.frame = NSRect(x: padding, y: y, width: width, height: 32)
        y -= 28
        letterLabel.frame = NSRect(x: padding, y: y, width: width, height: 20)
        y -= 30
        errorLabel.frame = NSRect(x: padding, y: y, width: width, height: 24)
        saveButton.frame = NSRect(
            x: contentView.bounds.width - padding - 110, y: padding, width: 110, height: 32)
        cancelButton.frame = NSRect(x: saveButton.frame.minX - 96, y: padding, width: 88, height: 32)
    }

    private func applyLocalization() {
        titleLabel.stringValue = MacUiText.text("Сохранить пакет", language: language)
        directoryLabel.stringValue = MacUiText.text("Куда", language: language)
        browseButton.title = MacUiText.text("Обзор…", language: language)
        subfolderBox.title = MacUiText.text("Создать подпапку", language: language)
        nameLabel.stringValue = MacUiText.text("Имя папки", language: language)
        hintLabel.stringValue = MacUiText.text(
            "В папку лягут снимки и prompt.md, текст с комментариями для ИИ", language: language)
        letterLabel.stringValue = MacUiText.text(
            "Снимки в пакете нумеруются заново: A, B, C…", language: language)
        cancelButton.title = MacUiText.text("Отмена", language: language)
        saveButton.title = MacUiText.text("Сохранить", language: language)
    }

    // Without a subfolder the files go straight into the chosen folder under a date prefix, so the
    // name of a folder that is not created has nothing to describe.
    private func updateNameState() {
        let enabled = subfolderBox.state == .on
        nameLabel.isEnabled = enabled
        nameField.isEnabled = enabled
    }

    @objc private func subfolderChanged() { updateNameState() }

    @objc private func browseClicked() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: directoryField.stringValue)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directoryField.stringValue = url.path
    }

    @objc private func cancelClicked() { window?.close() }

    @objc private func saveClicked() {
        guard let choice = validate() else { return }
        result = choice
        window?.close()
    }

    /// The checks of `OnSave`, apart from the window: the folder has to be named and absolute, and
    /// the name of a subfolder has to be a name a folder can carry.
    func validate() -> SavePackageChoice? {
        let directory = directoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if directory.isEmpty {
            return refuse("Укажите папку сохранения.")
        }
        // A relative path would be resolved against the working directory of the process, and the
        // package would land somewhere the user never named.
        let expanded = (directory as NSString).expandingTildeInPath
        if !expanded.hasPrefix("/") {
            return refuse("Укажите полный путь к папке, например /Users/Shared/Pictures.")
        }
        let createSubfolder = subfolderBox.state == .on
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if createSubfolder && name.isEmpty {
            return refuse("Укажите имя папки.")
        }
        // A slash is the one character a folder name cannot carry on this platform, and a leading dot
        // hides the folder the package was saved into.
        if createSubfolder && (name.contains("/") || name.contains(":") || name.hasPrefix(".")) {
            return refuse("В имени папки есть недопустимые символы.")
        }
        errorLabel.isHidden = true
        return SavePackageChoice(
            directory: URL(fileURLWithPath: expanded).standardizedFileURL.path,
            createSubfolder: createSubfolder, folderName: name)
    }

    private func refuse(_ russian: String) -> SavePackageChoice? {
        errorLabel.stringValue = MacUiText.text(russian, language: language)
        errorLabel.isHidden = false
        result = nil
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?(result)
    }
}
