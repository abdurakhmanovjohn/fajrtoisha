import Foundation

/// A calendar day with no time or timezone, like Python's `datetime.date`.
/// Stored as "yyyy-MM-dd" so changing timezone never shifts logged days.
nonisolated struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    /// Gregorian calendar in UTC, used purely for date arithmetic.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = AppConfig.firstWeekday
        return cal
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
        // Reject values like 2026-02-31 that Calendar would silently roll over.
        guard let date = Day.utcCalendar.date(from: components),
              Day(date, in: Day.utcCalendar.timeZone) == self else { return nil }
    }

    /// The day containing `date` in `timeZone` (user_local_date).
    init(_ date: Date, in timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    static func today(in timeZone: TimeZone, now: Date = .now) -> Day {
        Day(now, in: timeZone)
    }

    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { key }

    private var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: 12)
    }

    private var utcNoon: Date { Day.utcCalendar.date(from: components)! }

    func adding(days: Int) -> Day {
        Day(Day.utcCalendar.date(byAdding: .day, value: days, to: utcNoon)!, in: Day.utcCalendar.timeZone)
    }

    /// Number of days from `self` to `other` (other - self).
    func days(to other: Day) -> Int {
        Day.utcCalendar.dateComponents([.day], from: utcNoon, to: other.utcNoon).day!
    }

    /// Monday = 0 ... Sunday = 6, like Python's `date.weekday()`.
    var weekdayIndex: Int {
        let weekday = Day.utcCalendar.component(.weekday, from: utcNoon) // Sunday = 1
        return (weekday + 5) % 7
    }

    var isLastDayOfMonth: Bool { adding(days: 1).month != month }

    /// The absolute moment of `hour:minute` on this day in `timeZone`.
    func date(hour: Int, minute: Int, in timeZone: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    /// Start of the day in `timeZone`, for DatePicker interop.
    func startDate(in timeZone: TimeZone) -> Date {
        date(hour: 0, minute: 0, in: timeZone) ?? utcNoon
    }

    static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Inclusive range of days.
    static func range(_ start: Day, _ end: Day) -> [Day] {
        guard start <= end else { return [] }
        return (0...start.days(to: end)).map { start.adding(days: $0) }
    }
}
