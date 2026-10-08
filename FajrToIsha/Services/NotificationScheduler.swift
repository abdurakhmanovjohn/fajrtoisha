import Foundation
import UserNotifications

/// Applies a NotificationPlanner plan to UNUserNotificationCenter (replaces APScheduler).
final class NotificationScheduler {
    static let testIdentifier = "test_notification"

    private var center: UNUserNotificationCenter { .current() }

    /// Registers the "Mark as Prayed" action. Call at launch.
    func registerCategories() {
        let markPrayed = UNNotificationAction(identifier: NotificationPlanner.markPrayedAction,
                                              title: "Mark as Prayed", options: [])
        let exact = UNNotificationCategory(identifier: NotificationPlanner.exactCategory,
                                           actions: [markPrayed], intentIdentifiers: [], options: [])
        let summary = UNNotificationCategory(identifier: NotificationPlanner.summaryCategory,
                                             actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([exact, summary])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces the pending queue with `plan`. Identifiers are stable, so this is idempotent:
    /// anything not in the plan is removed and every planned request is (re)added.
    func apply(_ plan: [PlannedNotification]) async {
        let wanted = Set(plan.map(\.id))
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = pending.filter { !wanted.contains($0) && $0 != Self.testIdentifier }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.day.key
            var info: [String: String] = ["day": item.day.key, "kind": item.kind.rawValue]
            if let prayer = item.prayer { info["prayer"] = prayer }
            content.userInfo = info
            switch item.kind {
            case .exact: content.categoryIdentifier = NotificationPlanner.exactCategory
            case .summary: content.categoryIdentifier = NotificationPlanner.summaryCategory
            default: break
            }
            if item.kind == .exact || item.kind == .fajrEndWarning {
                content.interruptionLevel = .timeSensitive
            }

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                print("Failed to schedule \(item.id): \(error.localizedDescription)")
            }
        }
    }

    /// Called when a prayer is logged: drop its adhan alert (and the Fajr-end warning).
    func prayerLogged(_ name: String, day: Day) {
        var ids = [PlannedNotification.identifier(day: day, name: name, kind: .exact)]
        if name == "Fajr" { ids.append(PlannedNotification.identifier(day: day, name: name, kind: .fajrEndWarning)) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: [ids[0]])
    }

    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    /// Port of /test.
    func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Test notification."
        content.body = "If this arrived as a notification, your alerts are working. "
            + "If it was silent, enable notifications for this app in iOS Settings."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.testIdentifier, content: content, trigger: trigger))
    }

    /// Upcoming alerts for one day, for the "View Schedule" list.
    func pendingAlerts(on day: Day) async -> [(id: String, date: Date)] {
        let prefix = day.key + "_"
        return await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(prefix) }
            .compactMap { req in
                guard let trigger = req.trigger as? UNCalendarNotificationTrigger,
                      let date = trigger.nextTriggerDate() else { return nil }
                return (req.identifier, date)
            }
            .sorted { $0.date < $1.date }
    }
}
