import SwiftData
import SwiftUI
import UserNotifications
import RepTollShared

@main
struct RepTollApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                #if DEBUG
                .demoModelContainer()
                #endif
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
                .task { await Store.shared.refresh() }
        }
        .modelContainer(for: WorkoutRecord.self)
    }
}

/// The notification delegate methods stay main-actor isolated: UIKit asserts if the completion of
/// `didReceive` comes back off the main thread, which crashed the app when opened from the shield's banner.
final class AppDelegate: NSObject, UIApplicationDelegate, @MainActor UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let action = response.notification.request.content.userInfo[ShieldNotification.actionKey] as? String
        guard action == ShieldNotification.openUnlock else { return }
        AppModel.shared.handleShieldTap()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
