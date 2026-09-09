// Port of `WindowsStartupService.cs`, SPEC §1.18, §9.4.
import Foundation
import ServiceManagement

/// macOS equivalent of the Windows `HKCU\...\Run` registry value, using `SMAppService.mainApp`
/// (macOS 13+). Unlike Windows, macOS cannot verify the registration points at *this* exact
/// process's command line — the system binds registration to the bundle identifier instead
/// (SPEC §9.4).
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
