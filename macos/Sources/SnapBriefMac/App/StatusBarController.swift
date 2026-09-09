// Port of the tray icon and its context menu (`EdgeStackWindow.xaml.cs:76-113`), SPEC §1.1, §9.7.
import AppKit

/// `NSStatusItem` equivalent of the Windows tray icon. Left click shows the stack, right/Control
/// click opens the menu (macOS cannot distinguish a double click on a status item — SPEC §9.7).
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let showItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let newCaptureItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private let startupItem = NSMenuItem()

    private var language: String

    var onShowStack: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onNewCapture: (() -> Void)?
    var onQuit: (() -> Void)?
    var onLaunchAtLoginError: ((String) -> Void)?

    init(language: String) {
        self.language = language
        super.init()
        configureButton()
        configureMenu()
        applyLocalization()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // CHECK-API: SF Symbol name `camera.viewfinder` assumed available on macOS 14; verify on
        // a real machine and fall back to a bundled asset if not.
        button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapBrief")
        button.image?.isTemplate = true
        button.toolTip = "SnapBrief"
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        menu.delegate = self

        showItem.target = self
        showItem.action = #selector(showStackClicked)
        menu.addItem(showItem)

        settingsItem.target = self
        settingsItem.action = #selector(openSettingsClicked)
        menu.addItem(settingsItem)

        newCaptureItem.target = self
        newCaptureItem.action = #selector(newCaptureClicked)
        menu.addItem(newCaptureItem)

        menu.addItem(.separator())

        quitItem.target = self
        quitItem.action = #selector(quitClicked)
        menu.addItem(quitItem)

        startupItem.target = self
        startupItem.action = #selector(toggleStartup)
        menu.addItem(startupItem)
    }

    func updateLanguage(_ language: String) {
        self.language = language
        applyLocalization()
    }

    private func applyLocalization() {
        showItem.title = MacUiText.text("Показать стопку", language: language)
        settingsItem.title = MacUiText.text("Настройки", language: language)
        newCaptureItem.title = MacUiText.text("Новый снимок", language: language)
        quitItem.title = MacUiText.text("Выйти", language: language)
        // Port of §9.4: menu wording adapted to "Запускать при входе" / "Start at login".
        startupItem.title = MacUiText.text("Запускать с Windows", language: language)
    }

    /// Port of the tray menu's `Opening` handler (`:90-95`): re-translate and re-read the
    /// autostart checkbox every time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        applyLocalization()
        startupItem.state = LaunchAtLoginService.isEnabled ? .on : .off
        startupItem.isEnabled = true
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            // CHECK-API: temporary `statusItem.menu` assignment is the standard way to show a
            // menu from a status item button that also has its own left-click action.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onShowStack?()
        }
    }

    @objc private func showStackClicked() { onShowStack?() }

    @objc private func openSettingsClicked() {
        onShowStack?()
        onOpenSettings?()
    }

    @objc private func newCaptureClicked() { onNewCapture?() }

    @objc private func quitClicked() { onQuit?() }

    @objc private func toggleStartup() {
        do {
            try LaunchAtLoginService.setEnabled(!LaunchAtLoginService.isEnabled)
            startupItem.state = LaunchAtLoginService.isEnabled ? .on : .off
        } catch {
            onLaunchAtLoginError?("\(error)")
        }
    }
}
