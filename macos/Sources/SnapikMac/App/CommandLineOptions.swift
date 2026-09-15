// Port of `LaunchOptions.Parse` (`src/Snapik.App/App.xaml.cs:105-117`), SPEC §1.19.
import Foundation

struct CommandLineOptions: Equatable {
    let demo: Bool
    let smokeTest: Bool
    /// The resolved data root: `--data-dir`/`SNAPIK_DATA_DIR` if given, else a synthesized
    /// `{TEMP}/Snapik/demo-{pid}` for `--demo`, else `nil` (platform default,
    /// `SnapikPaths.defaultSessionsDirectory()`'s parent).
    let dataDirectory: URL?
    /// `--demo-screenshot <dir>`: after showing the demo stack/overlay, dump window screenshots
    /// here and exit (SPEC §1.19, CI-only flag documented in CONTRACTS "Shell").
    let demoScreenshotDirectory: URL?
    /// `--capture-test <path.png>` (CI-only, CONTRACTS "Shell"): performs one real
    /// `ScreenCaptureService.captureDesktop` and writes the frame to this path, to verify
    /// ScreenCaptureKit/Screen Recording actually works end-to-end on the CI runner.
    let captureTestPath: URL?

    /// Port of `LaunchOptions.Parse`: case-insensitive flag names, `--data-dir` takes the *last*
    /// occurrence, `SNAPIK_DATA_DIR` is used only when `--data-dir` was not given at all.
    static func parse(arguments: [String], environment: [String: String]) -> CommandLineOptions {
        var demo = false
        var smokeTest = false
        var explicitDataDir: String?
        var demoScreenshotDir: String?
        var captureTestPath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument.lowercased() {
            case "--demo":
                demo = true
            case "--smoke-test":
                smokeTest = true
            case "--data-dir":
                if index + 1 < arguments.count {
                    explicitDataDir = arguments[index + 1]
                    index += 1
                }
            case "--demo-screenshot":
                if index + 1 < arguments.count {
                    demoScreenshotDir = arguments[index + 1]
                    index += 1
                }
            case "--capture-test":
                if index + 1 < arguments.count {
                    captureTestPath = arguments[index + 1]
                    index += 1
                }
            default:
                break
            }
            index += 1
        }

        let resolvedExplicit = explicitDataDir ?? environment["SNAPIK_DATA_DIR"]
        var dataDirectory: URL?
        if let resolvedExplicit, !resolvedExplicit.isEmpty {
            dataDirectory = URL(fileURLWithPath: resolvedExplicit)
        } else if demo {
            let pid = ProcessInfo.processInfo.processIdentifier
            dataDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Snapik", isDirectory: true)
                .appendingPathComponent("demo-\(pid)", isDirectory: true)
        }

        return CommandLineOptions(
            demo: demo,
            smokeTest: smokeTest,
            dataDirectory: dataDirectory,
            demoScreenshotDirectory: demoScreenshotDir.map { URL(fileURLWithPath: $0) },
            captureTestPath: captureTestPath.map { URL(fileURLWithPath: $0) })
    }

    static func parseCurrentProcess() -> CommandLineOptions {
        parse(
            arguments: Array(CommandLine.arguments.dropFirst()),
            environment: ProcessInfo.processInfo.environment)
    }
}
