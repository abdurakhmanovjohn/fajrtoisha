import Foundation
import SwiftData

/// One row per prayer per day (port of `prayer_logs`).
@Model
final class PrayerLog {
    /// Enforces UNIQUE(prayer_name, prayer_date, category).
    @Attribute(.unique) var uniqueKey: String
    var prayerName: String
    /// Calendar day as "yyyy-MM-dd".
    var day: String
    var isCompleted: Bool
    /// "fard" or "nafl".
    var category: String

    init(prayerName: String, day: Day, isCompleted: Bool, category: LogCategory) {
        self.uniqueKey = PrayerLog.key(prayerName, day, category)
        self.prayerName = prayerName
        self.day = day.key
        self.isCompleted = isCompleted
        self.category = category.rawValue
    }

    static func key(_ name: String, _ day: Day, _ category: LogCategory) -> String {
        "\(category.rawValue)|\(name)|\(day.key)"
    }

    var record: LogRecord? {
        guard let d = Day(key: day), let c = LogCategory(rawValue: category) else { return nil }
        return LogRecord(prayerName: prayerName, day: d, isCompleted: isCompleted, category: c)
    }
}

/// Missed-prayer balances (port of `qaza`).
@Model
final class Qaza {
    @Attribute(.unique) var prayerName: String
    /// Never below zero.
    private(set) var remaining: Int

    init(prayerName: String, remaining: Int = 0) {
        self.prayerName = prayerName
        self.remaining = max(0, remaining)
    }

    /// GREATEST(0, remaining + delta)
    func adjust(by delta: Int) {
        remaining = max(0, remaining + delta)
    }
}

/// Cached Aladhan timings for one day at one location/method/school.
@Model
final class CachedTimings {
    /// "<locationKey>#yyyy-MM-dd"
    @Attribute(.unique) var id: String
    var locationKey: String
    var day: String
    var timezoneID: String
    var fajr: String
    var sunrise: String
    var dhuhr: String
    var asr: String
    var maghrib: String
    var isha: String
    var fetchedAt: Date

    init(locationKey: String, day: Day, timezoneID: String, timings: DayTimings, fetchedAt: Date = .now) {
        self.id = "\(locationKey)#\(day.key)"
        self.locationKey = locationKey
        self.day = day.key
        self.timezoneID = timezoneID
        self.fajr = timings.fajr
        self.sunrise = timings.sunrise
        self.dhuhr = timings.dhuhr
        self.asr = timings.asr
        self.maghrib = timings.maghrib
        self.isha = timings.isha
        self.fetchedAt = fetchedAt
    }

    func update(timezoneID: String, timings: DayTimings) {
        self.timezoneID = timezoneID
        fajr = timings.fajr
        sunrise = timings.sunrise
        dhuhr = timings.dhuhr
        asr = timings.asr
        maghrib = timings.maghrib
        isha = timings.isha
        fetchedAt = .now
    }

    var timings: DayTimings {
        DayTimings(fajr: fajr, sunrise: sunrise, dhuhr: dhuhr, asr: asr, maghrib: maghrib, isha: isha)
    }
}

/// Plain value copy of a `PrayerLog`, used by the pure StatsEngine.
nonisolated struct LogRecord: Hashable, Sendable {
    let prayerName: String
    let day: Day
    let isCompleted: Bool
    let category: LogCategory
}
