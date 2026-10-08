import BackgroundTasks
import Foundation
import Observation
import SwiftData
import UserNotifications

enum AppTab: Hashable {
    case today, log, stats, qaza, settings
}

enum StatsSection: String, CaseIterable, Identifiable {
    case reports = "Reports"
    case overview = "Overview"
    case profile = "Profile"
    var id: String { rawValue }
}

/// App-wide state and orchestration: settings, services, and the notification queue.
@Observable
final class AppModel {
    static let shared = AppModel()

    let container: ModelContainer
    let settings: SettingsStore
    @ObservationIgnored let prayerTimes: PrayerTimesService
    @ObservationIgnored let logs: LogStore
    @ObservationIgnored let notifications = NotificationScheduler()
    @ObservationIgnored let location = LocationManager()

    var selectedTab: AppTab = .today
    var statsSection: StatsSection = .reports
    /// Bumped whenever cached timings change so views re-read them.
    private(set) var timingsVersion = 0
    private(set) var isRefreshing = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(inMemory: Bool = false) {
        let schema = Schema([PrayerLog.self, Qaza.self, CachedTimings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        settings = SettingsStore()
        prayerTimes = PrayerTimesService(context: container.mainContext)
        logs = LogStore(context: container.mainContext)
    }

    // MARK: Time

    var timeZone: TimeZone { settings.timeZone }

    func today(now: Date = .now) -> Day { Day.today(in: timeZone, now: now) }

    func timings(for day: Day) -> ResolvedTimings? {
        _ = timingsVersion
        guard let query = settings.locationQuery else { return nil }
        return prayerTimes.timings(for: day, query: query, method: settings.calcMethod, school: settings.asrSchool)
    }

    func adhan(_ name: String, on day: Day) -> Date? {
        guard let t = timings(for: day) else { return nil }
        return t.timings.date(of: name, on: day, in: t.timeZone)
    }

    // MARK: Location setup (port of location_handler)

    /// Fetches the current month for `query`, stores the location and Aladhan's timezone,
    /// and returns today's timings.
    func setLocation(_ query: LocationQuery) async throws -> ResolvedTimings {
        let probeTZ = settings.timezoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let probeDay = Day.today(in: probeTZ)
        let month = try await prayerTimes.fetchAndStore(query, method: settings.calcMethod, school: settings.asrSchool,
                                                        year: probeDay.year, month: probeDay.month)
        settings.setLocation(query, timezoneID: month.timezoneID)
        let today = today()
        if today.month != probeDay.month || today.year != probeDay.year {
            _ = try? await prayerTimes.fetchAndStore(query, method: settings.calcMethod, school: settings.asrSchool,
                                                 year: today.year, month: today.month)
        }
        timingsVersion += 1
        guard let resolved = timings(for: today) else { throw PrayerTimesError.noData }
        return resolved
    }

    // MARK: Refresh (replaces daily_scheduler_job)

    /// Ensures timings are cached and rebuilds the notification queue. Calls are serialized.
    func refresh() async {
        let previous = refreshTask
        let task = Task {
            await previous?.value
            await performRefresh()
        }
        refreshTask = task
        await task.value
    }


    private func performRefresh() async {
        guard settings.hasOnboarded, let query = settings.locationQuery else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if let tz = await prayerTimes.ensureCached(query, method: settings.calcMethod,
                                                    school: settings.asrSchool, today: today()) {
            if tz != settings.timezoneID { settings.timezoneID = tz }
        }
        timingsVersion += 1
        await rebuildNotifications()
        scheduleBackgroundRefresh()
    }

    func rebuildNotifications(now: Date = .now) async {
        guard settings.hasOnboarded, settings.locationQuery != nil else { return }
        let status = await notifications.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let plan = NotificationPlanner.plan(
            now: now,
            today: today(now: now),
            timeZone: timeZone,
            offsetMinutes: settings.reminderOffsetMins,
            timings: { [self] day in timings(for: day)?.timings },
            isCompleted: { [self] name, day in logs.isCompleted(name, day: day) }
        )
        await notifications.apply(plan)
    }

    // MARK: Logging

    func toggleFard(_ name: String, day: Day, now: Date = .now) -> LogStore.ToggleResult {
        let today = today(now: now)
        let result = logs.toggleFard(name, day: day, today: today, now: now,
                                     adhan: day == today ? adhan(name, on: day) : nil, timeZone: timeZone)
        if case .changed(true) = result { notifications.prayerLogged(name, day: day) }
        return result
    }

    /// "Mark as Prayed" from the adhan notification (no toggle, always sets completed).
    func markPrayedFromNotification(prayer: String, dayKey: String) {
        guard let day = Day(key: dayKey), day <= today(), Prayers.fard.contains(prayer) else { return }
        logs.set(prayer, day: day, category: .fard, completed: true)
        notifications.prayerLogged(prayer, day: day)
    }

    // MARK: Danger zone

    func resetPrayerLogs() async {
        logs.resetLogs()
        await rebuildNotifications()
    }

    func deleteAllData() {
        notifications.removeAll()
        BGTaskScheduler.shared.cancelAllTaskRequests()
        logs.deleteAll()
        prayerTimes.deleteAll()
        settings.resetAll()
        selectedTab = .today
        timingsVersion += 1
    }

    // MARK: Background refresh

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected on the simulator, which doesn't support background tasks.
            print("BGTaskScheduler submit failed: \(error.localizedDescription)")
        }
    }

    // MARK: Notification responses

    func handleNotificationResponse(action: String, userInfo: [String: String]) {
        if action == NotificationPlanner.markPrayedAction,
           let prayer = userInfo["prayer"], let day = userInfo["day"] {
            markPrayedFromNotification(prayer: prayer, dayKey: day)
            return
        }
        guard action == UNNotificationDefaultActionIdentifier else { return }
        if userInfo["kind"] == PlannedNotification.Kind.summary.rawValue {
            statsSection = .reports
            selectedTab = .stats
        } else if userInfo["kind"] != nil {
            selectedTab = .today
        }
    }
}
