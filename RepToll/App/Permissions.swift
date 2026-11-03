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
    private(set) var screenTimeStatus = AuthorizationStatus.notDetermined
    /// FamilyControls reports `.notDetermined` for a moment at launch before the real status loads.
    private var screenTimeSettled = false

    /// Screen Time really isn't usable: denied, or still not determined once the status has had time to load.
    var screenTimeMissing: Bool {
        screenTimeStatus == .denied || (screenTimeStatus == .notDetermined && screenTimeSettled)
    }

    var allGranted: Bool { screenTime && camera && notifications }

    func refresh() async {
        setScreenTime(AuthorizationCenter.shared.authorizationStatus)
        camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = settings.authorizationStatus == .authorized
        isLoaded = true
    }

    /// Follows the live Screen Time status for as long as the calling view's task runs.
    func watchScreenTime() async {
        let settle = Task {
            try? await Task.sleep(for: .seconds(2))
            screenTimeSettled = true
        }
        defer { settle.cancel() }
        for await status in AuthorizationCenter.shared.$authorizationStatus.values {
            setScreenTime(status)
        }
    }

    private func setScreenTime(_ status: AuthorizationStatus) {
        screenTimeStatus = status
        screenTime = status == .approved
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
