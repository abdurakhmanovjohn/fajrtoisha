import Foundation

/// A local notification to be scheduled. Pure value, no UserNotifications dependency.
nonisolated struct PlannedNotification: Hashable, Sendable {
    enum Kind: String, Sendable {
        case warning          // heads-up N minutes before a prayer
        case exact            // at adhan time, with "Mark as Prayed"
        case fajrEndWarning   // N minutes before sunrise
        case fajrEnded        // at sunrise
        case summary          // 21:00 end-of-day prompt
    }

    /// Stable identifier, e.g. "2026-10-08_Asr_exact". Rebuilding is idempotent.
    let id: String
    let kind: Kind
    let day: Day
    let prayer: String?
    let fireDate: Date
    let title: String
    let body: String

    static func identifier(day: Day, name: String, kind: Kind) -> String {
        switch kind {
        case .warning: "\(day.key)_\(name)_warning"
        case .exact: "\(day.key)_\(name)_exact"
        case .fajrEndWarning: "\(day.key)_Sunrise_warning"
        case .fajrEnded: "\(day.key)_Sunrise_exact"
        case .summary: "\(day.key)_summary"
        }
    }
}

/// Port of daily_scheduler_job, extended to a rolling multi-day window.
nonisolated enum NotificationPlanner {
    /// iOS keeps at most 64 pending local notifications per app.
    static let systemLimit = 64
    /// One slot is kept free for the "Send test notification" button.
    static let defaultLimit = systemLimit - 1
    static let windowDays = 5

    static let markPrayedAction = "MARK_PRAYED"
    static let exactCategory = "PRAYER_EXACT"
    static let summaryCategory = "DAILY_SUMMARY"

    /// Builds the notification queue for `days` days starting at `today`.
    /// - Parameters:
    ///   - timings: timings for a day, or nil if unknown (that day is skipped).
    ///   - isCompleted: whether a fard prayer is already logged for that day.
    /// - Returns: future notifications sorted by fire date, never more than `limit`.
    static func plan(
        now: Date,
        today: Day,
        timeZone: TimeZone,
        offsetMinutes: Int,
        days: Int = windowDays,
        limit: Int = defaultLimit,
        timings: (Day) -> DayTimings?,
        isCompleted: (String, Day) -> Bool
    ) -> [PlannedNotification] {
        let cappedLimit = max(0, min(limit, systemLimit))
        let lead = TimeInterval(offsetMinutes * 60)
        var result: [PlannedNotification] = []

        func add(_ kind: PlannedNotification.Kind, _ day: Day, _ name: String?, _ date: Date,
                 _ title: String, _ body: String) {
            guard date > now else { return }
            let id = PlannedNotification.identifier(day: day, name: name ?? "", kind: kind)
            result.append(.init(id: id, kind: kind, day: day, prayer: name, fireDate: date,
                                title: title, body: body))
        }

        for offset in 0..<max(0, days) {
            let day = today.adding(days: offset)
            guard let t = timings(day) else { continue }

            for name in Prayers.timingNames {
                guard let event = t.date(of: name, on: day, in: timeZone) else { continue }

                if name == "Sunrise" {
                    // Fajr-end reminders. The warning is pointless once Fajr is logged.
                    if !isCompleted("Fajr", day) {
                        add(.fajrEndWarning, day, name, event - lead,
                            "Fajr ends in \(offsetMinutes) minutes.",
                            "If you haven't prayed Fajr yet, hurry before sunrise.")
                    }
                    add(.fajrEnded, day, name, event,
                        "Fajr time has ended.",
                        "The sun has risen — Fajr is over for today.")
                    continue
                }

                add(.warning, day, name, event - lead,
                    "\(name) is approaching!",
                    "Take a moment to prepare and make Wudu.")
                if !isCompleted(name, day) {
                    add(.exact, day, name, event,
                        "It is time for \(name).",
                        "Adhan at \(TimeOfDay.format(event, in: timeZone)).")
                }
            }

            if let summary = day.date(hour: AppConfig.summaryHour, minute: 0, in: timeZone) {
                add(.summary, day, nil, summary, "End-of-day summary", summaryBody(for: day))
            }
        }

        result.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(result.prefix(cappedLimit))
    }

    /// Content is fixed at schedule time, so the summary is a prompt to open the app.
    static func summaryBody(for day: Day) -> String {
        let weekly = day.weekdayIndex == 6        // Sunday
        let monthly = day.isLastDayOfMonth
        var body = "Tap to see today's summary."
        switch (weekly, monthly) {
        case (true, true): body += " Your weekly and monthly recaps are ready too."
        case (true, false): body += " Your weekly recap is ready too."
        case (false, true): body += " Your monthly recap is ready too."
        case (false, false): break
        }
        return body
    }
}
