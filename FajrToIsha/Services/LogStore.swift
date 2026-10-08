import Foundation
import SwiftData

/// Reads and writes prayer logs and qaza balances (the SQL in the bot's handlers).
final class LogStore {
    enum ToggleResult: Equatable {
        case changed(isCompleted: Bool)
        /// "It is not time for X yet. Adhan is at HH:MM."
        case notTimeYet(prayer: String, adhan: String)
        case futureDate
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Prayer logs

    func log(_ name: String, day: Day, category: LogCategory) -> PrayerLog? {
        let key = PrayerLog.key(name, day, category)
        var descriptor = FetchDescriptor<PrayerLog>(predicate: #Predicate { $0.uniqueKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func isCompleted(_ name: String, day: Day, category: LogCategory = .fard) -> Bool {
        log(name, day: day, category: category)?.isCompleted ?? false
    }

    func completed(on day: Day, category: LogCategory) -> Set<String> {
        let key = day.key
        let raw = category.rawValue
        let descriptor = FetchDescriptor<PrayerLog>(predicate: #Predicate {
            $0.day == key && $0.category == raw && $0.isCompleted
        })
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.prayerName))
    }

    func allRecords() -> [LogRecord] {
        ((try? context.fetch(FetchDescriptor<PrayerLog>())) ?? []).compactMap(\.record)
    }

    /// Upsert (INSERT ... ON CONFLICT DO UPDATE).
    func set(_ name: String, day: Day, category: LogCategory, completed: Bool) {
        if let existing = log(name, day: day, category: category) {
            existing.isCompleted = completed
        } else {
            context.insert(PrayerLog(prayerName: name, day: day, isCompleted: completed, category: category))
        }
        try? context.save()
    }

    /// Port of log_prayer_handler's menu path: toggle with the future-date and adhan time gates.
    /// - Parameter adhan: today's adhan moment for this prayer, if known.
    func toggleFard(_ name: String, day: Day, today: Day, now: Date, adhan: Date?, timeZone: TimeZone) -> ToggleResult {
        guard day <= today else { return .futureDate }
        let newState = !isCompleted(name, day: day)
        if newState, day == today, let adhan, adhan > now {
            return .notTimeYet(prayer: name, adhan: TimeOfDay.format(adhan, in: timeZone))
        }
        set(name, day: day, category: .fard, completed: newState)
        return .changed(isCompleted: newState)
    }

    /// Port of nafl_set_handler: toggle, future dates blocked, no time gate.
    func toggleNafl(_ name: String, day: Day, today: Day) -> ToggleResult {
        guard day <= today else { return .futureDate }
        let newState = !isCompleted(name, day: day, category: .nafl)
        set(name, day: day, category: .nafl, completed: newState)
        return .changed(isCompleted: newState)
    }

    /// "Reset prayer logs": DELETE FROM prayer_logs.
    func resetLogs() {
        try? context.delete(model: PrayerLog.self)
        try? context.save()
    }

    // MARK: Qaza

    func qazaBalances() -> [String: Int] {
        let rows = (try? context.fetch(FetchDescriptor<Qaza>())) ?? []
        let found = Dictionary(rows.map { ($0.prayerName, $0.remaining) }, uniquingKeysWith: { a, _ in a })
        return Dictionary(uniqueKeysWithValues: Prayers.qaza.map { ($0, found[$0] ?? 0) })
    }

    @discardableResult
    func adjustQaza(_ name: String, by delta: Int) -> Int {
        var descriptor = FetchDescriptor<Qaza>(predicate: #Predicate { $0.prayerName == name })
        descriptor.fetchLimit = 1
        let row: Qaza
        if let existing = try? context.fetch(descriptor).first {
            row = existing
            row.adjust(by: delta)
        } else {
            row = Qaza(prayerName: name, remaining: delta)
            context.insert(row)
        }
        try? context.save()
        return row.remaining
    }

    // MARK: Delete everything

    func deleteAll() {
        try? context.delete(model: PrayerLog.self)
        try? context.delete(model: Qaza.self)
        try? context.save()
    }
}
