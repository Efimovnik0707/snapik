// Port of `App.xaml.cs`'s `OnStartup` entry sequence, SPEC §1.18-§1.19, §9.6.
import AppKit
import Foundation
import SnapBriefCore

let options = CommandLineOptions.parseCurrentProcess()
StartupLog.write(options, "App.OnStartup entered")

if !options.smokeTest {
    // Port of the Windows named-mutex check (§1.18): `--smoke-test` never takes this path, so it
    // can run alongside a live instance (SPEC §1.18 point 7).
    if SingleInstanceCoordinator.activateExistingInstanceIfRunning() {
        StartupLog.write(options, "Second instance requested SHOW")
        exit(0)
    }
}

if options.smokeTest {
    let result = SmokeTestRunner.run(options: options)
    exit(result ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.run()
