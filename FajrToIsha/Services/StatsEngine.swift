import Foundation

/// Pure statistics functions, ported from the bot's compute_streaks, build_daily_report,
/// build_range_report, build_overview and profile_handler.
nonisolated enum StatsEngine {

    // MARK: - Queries (SQL equivalents)

    /// get_completed_prayers: names of completed fard prayers on `day`.
    static func completedFard(_ logs: [LogRecord], on day: Day) -> Set<String> {
        Set(logs.lazy.filter { $0.category == .fard && $0.isCompleted && $0.day == day }.map(\.prayerName))
    }

    /// get_completion_map: day -> COUNT(DISTINCT prayer_name) of completed fard, for days >= start.
    static func completionMap(_ logs: [LogRecord], from start: Day) -> [Day: Int] {
        var names: [Day: Set<String>] = [:]
        for log in logs where log.category == .fard && log.isCompleted && log.day >= start {
            names[log.day, default: []].insert(log.prayerName)
        }
        return names.mapValues(\.count)
    }

    /// SELECT MIN(prayer_date) FROM prayer_logs WHERE category = 'fard'
    /// (any row, completed or not, exactly as the bot does).
    static func firstFardLogDay(_ logs: [LogRecord]) -> Day? {
        logs.lazy.filter { $0.category == .fard }.map(\.day).min()
    }

    /// Python's round(): rounds half to even.
    static func pyRound(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    // MARK: - Streaks

    /// compute_streaks: an unfinished today does not break the current streak.
    static func computeStreaks(_ completeDays: [Day], today: Day) -> (current: Int, longest: Int) {
        let set = Set(completeDays)
        guard !set.isEmpty else { return (0, 0) }

        var current = 0
        var cursor = set.contains(today) ? today : today.adding(days: -1)
        while set.contains(cursor) {
            current += 1
            cursor = cursor.adding(days: -1)
        }

        var longest = 0
        var run = 0
        var prev: Day?
        for day in set.sorted() {
            if let p = prev, day == p.adding(days: 1) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            prev = day
        }
        return (current, longest)
    }

    // MARK: - Daily report

    struct DailyReport: Equatable, Sendable {
        let day: Day
        let completed: Set<String>
        var count: Int { completed.count }
        var isPerfect: Bool { count == 5 }
    }

    static func dailyReport(_ logs: [LogRecord], day: Day) -> DailyReport {
        DailyReport(day: day, completed: completedFard(logs, on: day))
    }

    // MARK: - Range report

    struct RangeReport: Equatable, Sendable {
        enum Outcome: Equatable, Sendable {
            case noPrayers
            case mostMissed(prayers: [String], times: Int)
            case perfect
        }

        let title: String
        let effectiveStart: Day
        let end: Day
        let numDays: Int
        let total: Int
        let possible: Int
        let rate: Int
        let perfectDays: Int
        /// Completed count per prayer, in `Prayers.fard` order.
        let perPrayer: [(name: String, count: Int)]
        let outcome: Outcome

        static func == (l: RangeReport, r: RangeReport) -> Bool {
            l.title == r.title && l.effectiveStart == r.effectiveStart && l.end == r.end
                && l.numDays == r.numDays && l.total == r.total && l.possible == r.possible
                && l.rate == r.rate && l.perfectDays == r.perfectDays && l.outcome == r.outcome
                && l.perPrayer.map(\.name) == r.perPrayer.map(\.name)
                && l.perPrayer.map(\.count) == r.perPrayer.map(\.count)
        }
    }

    static func rangeReport(_ logs: [LogRecord], start: Day, end: Day, title: String) -> RangeReport {
        var per: [String: Int] = [:]
        for log in logs where log.category == .fard && log.isCompleted && log.day >= start && log.day <= end {
            per[log.prayerName, default: 0] += 1
        }
        let firstLog = firstFardLogDay(logs)
        let cmap = completionMap(logs, from: start)

        let effectiveStart = firstLog.map { max(start, $0) } ?? end
        let numDays = effectiveStart.days(to: end) + 1
        let total = per.values.reduce(0, +)
        let possible = numDays * 5
        let rate = possible != 0 ? pyRound(Double(total) / Double(possible) * 100) : 0
        let fullDays = cmap.filter { $0.value == 5 && effectiveStart <= $0.key && $0.key <= end }.count

        let perPrayer = Prayers.fard.map { (name: $0, count: per[$0] ?? 0) }

        let outcome: RangeReport.Outcome
        if total == 0 {
            outcome = .noPrayers
        } else {
            let missed = Prayers.fard.map { numDays - (per[$0] ?? 0) }
            let maxMissed = missed.max() ?? 0
            if maxMissed > 0 {
                let worst = zip(Prayers.fard, missed).filter { $0.1 == maxMissed }.map(\.0)
                outcome = .mostMissed(prayers: worst, times: maxMissed)
            } else {
                outcome = .perfect
            }
        }

        return RangeReport(title: title, effectiveStart: effectiveStart, end: end, numDays: numDays,
                           total: total, possible: possible, rate: rate, perfectDays: fullDays,
                           perPrayer: perPrayer, outcome: outcome)
    }

    static func weeklyReport(_ logs: [LogRecord], today: Day) -> RangeReport {
        rangeReport(logs, start: today.adding(days: -6), end: today, title: "Weekly Report")
    }

    static func thirtyDayReport(_ logs: [LogRecord], today: Day, title: String = "30-Day Report") -> RangeReport {
        rangeReport(logs, start: today.adding(days: -29), end: today, title: title)
    }

    // MARK: - 30-day overview

    enum OverviewCell: Hashable, Sendable {
        /// Padding after today, or a day before tracking started.
        case outside(Day?)
        case tracked(Day, count: Int)
    }

    struct Overview: Equatable, Sendable {
        /// Monday-aligned rows of 7 cells.
        let weeks: [[OverviewCell]]
        let perfectDays: Int
        let trackedDays: Int
        let rate: Int
        let currentStreak: Int
    }

    static func overview(_ logs: [LogRecord], today: Day) -> Overview {
        let windowStart = today.adding(days: -29)
        let gridStart = windowStart.adding(days: -windowStart.weekdayIndex)
        let cmap = completionMap(logs, from: gridStart)
        let firstLog = firstFardLogDay(logs)

        let trackedStart = firstLog.map { max(windowStart, $0) } ?? today
        let trackedDays = trackedStart.days(to: today) + 1

        var cells: [Day?] = Day.range(gridStart, today)
        while cells.count % 7 != 0 { cells.append(nil) }

        let mapped: [OverviewCell] = cells.map { day in
            guard let day, day >= trackedStart else { return .outside(day) }
            return .tracked(day, count: cmap[day] ?? 0)
        }
        let weeks = stride(from: 0, to: mapped.count, by: 7).map { Array(mapped[$0..<$0 + 7]) }

        let perfect = cmap.filter { $0.value == 5 && $0.key >= trackedStart }.count
        let total = cmap.filter { $0.key >= trackedStart }.values.reduce(0, +)
        let rate = trackedDays != 0 ? pyRound(Double(total) / Double(trackedDays * 5) * 100) : 0
        let completeDays = cmap.filter { $0.value == 5 }.map(\.key)
        let (current, _) = computeStreaks(completeDays, today: today)

        return Overview(weeks: weeks, perfectDays: perfect, trackedDays: trackedDays,
                        rate: rate, currentStreak: current)
    }

    // MARK: - Profile

    struct Profile: Equatable, Sendable {
        let currentStreak: Int
        let longestStreak: Int
        let todayCount: Int
        let lifetimeTotal: Int
    }

    static func profile(_ logs: [LogRecord], today: Day) -> Profile {
        let completed = logs.filter { $0.category == .fard && $0.isCompleted }
        let todayCount = completed.filter { $0.day == today }.count
        let completeDays = completionMap(completed, from: Day(year: 1, month: 1, day: 1))
            .filter { $0.value == 5 }.map(\.key)
        let (current, longest) = computeStreaks(completeDays, today: today)
        return Profile(currentStreak: current, longestStreak: longest,
                       todayCount: todayCount, lifetimeTotal: completed.count)
    }

    // MARK: - Formatting helpers

    static func plural(_ n: Int, _ singular: String, _ pluralForm: String) -> String {
        "\(n) \(n == 1 ? singular : pluralForm)"
    }
}
