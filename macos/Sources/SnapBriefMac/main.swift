// Port of `App.xaml.cs`'s `OnStartup` entry sequence, SPEC §1.18-§1.19, §9.6.
import AppKit
import Foundation
import SnapBriefCore

let options = CommandLineOptions.parseCurrentProcess()
StartupLog.write(options, "App.OnStartup entered")

if !options.smokeTest, options.captureTestPath == nil {
    // Port of the Windows named-mutex check (§1.18): `--smoke-test`/`--capture-test` never take
    // this path, so either can run alongside a live instance (SPEC §1.18 point 7).
    if SingleInstanceCoordinator.activateExistingInstanceIfRunning() {
        StartupLog.write(options, "Second instance requested SHOW")
        exit(0)
    }
}

if options.smokeTest {
    // `SmokeTestRunner.run` awaits `@MainActor` work (`OverlayEditorController`,
    // `HotkeySettingsWindowController`, both `@MainActor`); those hops need a live main run loop
    // pumping `DispatchQueue.main`, which a synchronous `DispatchSemaphore.wait()` on this thread
    // would starve. So the smoke test runs the same way `--demo-screenshot` does: under a real
    // `NSApplication.run()`, kicked off once `applicationDidFinishLaunching` fires, exiting the
    // process with the matching code when it's done.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let smokeDelegate = SmokeTestAppDelegate(options: options)
    app.delegate = smokeDelegate
    app.run()
}

if let captureTestPath = options.captureTestPath {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let captureDelegate = CaptureTestAppDelegate(outputPath: captureTestPath)
    app.delegate = captureDelegate
    app.run()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Top-level code in main.swift is not main-actor-isolated in Swift 5 language mode; the process
// is on the main thread here, so assuming isolation is correct.
let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate(options: options) }
app.delegate = delegate
app.run()
