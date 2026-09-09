// Port of `Notify(message)` (`EdgeStackWindow.Saving.cs:9-14`), SPEC §1.15, §9.9.
import Foundation
import SnapBriefCore
import UserNotifications

/// Shows a transient system notification for "Снимок сохранён" / "Снимки скопированы" when the
/// "Уведомления о копировании и сохранении" setting is on. Permission is requested lazily, on the
/// first notification, not at startup (SPEC §9.9). Denial is not an error: the setting stays on,
/// notifications simply do not appear.
final class NotificationService {
    private var didRequestAuthorization = false

    /// `Bundle.main.bundleIdentifier` is `nil` when running as a bare executable (e.g. under
    /// `swift test`, or `--smoke-test` outside a `.app` bundle); `UNUserNotificationCenter` is not
    /// usable in that case, so every call becomes a no-op instead of crashing.
    private var isRunningInsideBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func notify(_ message: String, language: String) {
        guard isRunningInsideBundle else { return }

        requestAuthorizationIfNeeded { [weak self] granted in
            guard granted else { return }
            self?.post(message: message, language: language)
        }
    }

    private func requestAuthorizationIfNeeded(_ completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    completion(granted)
                }
            default:
                completion(false)
            }
        }
    }

    private func post(message: String, language: String) {
        let content = UNMutableNotificationContent()
        content.title = "SnapBrief"
        content.body = MacUiText.text(message, language: language)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
