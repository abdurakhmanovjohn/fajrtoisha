import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be set before launch finishes so background "Mark as Prayed" actions are delivered.
        UNUserNotificationCenter.current().delegate = self
        AppModel.shared.notifications.registerCategories()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let raw = response.notification.request.content.userInfo
        var info: [String: String] = [:]
        for (key, value) in raw {
            if let k = key as? String, let v = value as? String { info[k] = v }
        }
        await MainActor.run {
            AppModel.shared.handleNotificationResponse(action: action, userInfo: info)
        }
    }
}
