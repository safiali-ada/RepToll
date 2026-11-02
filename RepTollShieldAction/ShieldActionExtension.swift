import ManagedSettings
import UserNotifications
import RepTollShared

/// Handles the shield buttons. Extensions can't open the app directly, so the primary button
/// posts a notification that deep-links into RepToll's unlock screen.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            postOpenAppNotification()
            return .defer
        case .secondaryButtonPressed:
            return .close
        default:
            return .close
        }
    }

    private func postOpenAppNotification() {
        let banked = SharedStore.shared.bankSeconds / 60
        let content = UNMutableNotificationContent()
        content.title = "RepToll"
        content.body = banked > 0
            ? "Tap to choose how much of your \(banked) min to spend."
            : "Tap to earn time with a quick set."
        content.userInfo = [ShieldNotification.actionKey: ShieldNotification.openUnlock]
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: ShieldNotification.openUnlock, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
