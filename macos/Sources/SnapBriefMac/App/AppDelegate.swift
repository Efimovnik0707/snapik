// Port of `App.xaml.cs`'s non-single-instance startup path, SPEC §1.1, §1.18, §9.6, §9.7.
import AppKit
import SnapBriefCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: CommandLineOptions
    private var coordinator: AppCoordinator!
    private var statusBar: StatusBarController!
    private var stackWindow: EdgeStackWindowController!
    private var activationObserver: NSObjectProtocol?

    init(options: CommandLineOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupLog.write(options, "App.applicationDidFinishLaunching entered")

        coordinator = AppCoordinator(options: options)
        StartupLog.write(options, "Constructing EdgeStackWindow")
        statusBar = StatusBarController(language: coordinator.language)
        stackWindow = EdgeStackWindowController(coordinator: coordinator)
        coordinator.stackWindow = stackWindow
        coordinator.statusBar = statusBar
        StartupLog.write(options, "Primary window constructed")

        wireStatusBar()

        activationObserver = SingleInstanceCoordinator.observeActivationRequests { [weak self] in
            self?.stackWindow.reveal()
        }

        coordinator.start()
        StartupLog.write(options, "EdgeStack.Loaded entered")

        if options.demo, let screenshotDirectory = options.demoScreenshotDirectory {
            DemoSessionFactory.runScreenshotFlow(to: screenshotDirectory, coordinator: coordinator)
        }
    }

    private func wireStatusBar() {
        statusBar.onShowStack = { [weak self] in self?.stackWindow.reveal() }
        statusBar.onOpenSettings = { [weak self] in self?.stackWindow.openSettings() }
        statusBar.onNewCapture = { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.coordinator.newCapture() }
        }
        statusBar.onQuit = { NSApp.terminate(nil) }
        statusBar.onLaunchAtLoginError = { [weak self] message in
            self?.stackWindow.setStatus(StatusStrings.failedToToggleLaunchAtLogin(message), isError: true)
        }
    }

    /// Port of `OnClosing` (`:764-772`): force-save before quitting; if the save fails, cancel
    /// the quit and reveal the stack so the user sees why (SPEC §9.7).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor [weak self] in
            guard let self else {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            let saved = await self.coordinator.prepareForQuit()
            if saved {
                self.coordinator.shutdown()
                if let activationObserver = self.activationObserver {
                    SingleInstanceCoordinator.stopObserving(activationObserver)
                }
            }
            NSApp.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        // No-op: `EdgeStackWindowController.reveal()` recomputes its position from the current
        // screen every time it is shown, so no persistent geometry cache needs invalidating.
    }
}
