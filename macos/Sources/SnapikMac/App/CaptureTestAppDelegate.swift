// `--capture-test <path.png>` CI helper (CONTRACTS.md "Shell"): performs exactly one real
// `ScreenCaptureService.captureDesktop`, writes the frame to `outputPath`, and reports the
// outcome the way `scripts/ci-smoke.sh` expects (`OK capture WxH` / `FAIL capture: <error>` on
// stdout, exit code 0/1). Needs a real `NSApplication.run()` for the same reason `--smoke-test`
// does (`SmokeTestAppDelegate`): `ScreenCaptureService.captureDesktop`'s completion is dispatched
// onto the main queue, which needs a live run loop to actually drain.
import AppKit
import SnapikCore

final class CaptureTestAppDelegate: NSObject, NSApplicationDelegate {
    private let outputPath: URL
    private let captureService: ScreenCaptureServicing = ScreenCaptureService()
    private var finished = false

    init(outputPath: URL) {
        self.outputPath = outputPath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureService.captureDesktop(includeCursor: false) { [weak self] result in
            self?.finish(with: result)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            print("FAIL capture: timed out after 30s")
            exit(1)
        }
    }

    private func finish(with result: Result<DesktopFrame, Error>) {
        guard !finished else { return }
        finished = true

        switch result {
        case .success(let frame):
            guard let data = ImageCodec.encode(frame.image, format: .png) else {
                print("FAIL capture: could not encode the captured frame as PNG")
                exit(1)
            }
            do {
                try ImageCodec.writeAtomically(data, to: outputPath)
                print("OK capture \(frame.pixelWidth)x\(frame.pixelHeight)")
                exit(0)
            } catch {
                print("FAIL capture: \(error)")
                exit(1)
            }
        case .failure(let error):
            print("FAIL capture: \(error)")
            exit(1)
        }
    }
}
