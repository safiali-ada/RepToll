import AVFoundation
import FamilyControls
import Observation
import UserNotifications

@Observable
final class Permissions {
    private(set) var screenTime = false
    private(set) var camera = false
    private(set) var notifications = false
    /// False until the first `refresh()`, so screens don't flash "denied" before checking.
    private(set) var isLoaded = false

    var allGranted: Bool { screenTime && camera && notifications }

    func refresh() async {
        screenTime = AuthorizationCenter.shared.authorizationStatus == .approved
        camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = settings.authorizationStatus == .authorized
        isLoaded = true
    }

    func requestScreenTime() async {
        try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        await refresh()
    }

    func requestCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        await refresh()
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }
}
