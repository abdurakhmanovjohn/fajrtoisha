import SwiftData
import SwiftUI

/// Port of /log_prayers and /nafl: toggles for any past day.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @Query private var logs: [PrayerLog]
    @State private var selectedDay: Day?
    @State private var gateMessage: String?

    var body: some View {
        let today = model.today()
        let day = min(selectedDay ?? today, today)
        let dayLogs = logs.filter { $0.day == day.key && $0.isCompleted }
        let fard = Set(dayLogs.filter { $0.category == LogCategory.fard.rawValue }.map(\.prayerName))
        let nafl = Set(dayLogs.filter { $0.category == LogCategory.nafl.rawValue }.map(\.prayerName))

        NavigationStack {
            List {
                Section {
                    DayNavigator(day: Binding(get: { day }, set: { selectedDay = $0 }),
                                 today: today, timeZone: model.timeZone)
                }

                Section {
                    ForEach(Prayers.fard, id: \.self) { name in
                        let adhan = day == today ? model.adhan(name, on: day) : nil
                        PrayerToggleRow(name: name, isCompleted: fard.contains(name),
                                        detail: adhan.map { TimeOfDay.format($0, in: model.timeZone) },
                                        isLocked: (adhan ?? .distantPast) > .now) {
                            gateMessage = model.toggleFard(name, day: day).alertMessage
                        }
                    }
                } header: {
                    Text("Fard · \(fard.count)/5")
                } footer: {
                    Text("Tap a prayer to toggle it.")
                }

                Section {
                    ForEach(Prayers.nafl, id: \.self) { name in
                        PrayerToggleRow(name: name, isCompleted: nafl.contains(name)) {
                            gateMessage = model.logs.toggleNafl(name, day: day, today: today).alertMessage
                        }
                    }
                } header: {
                    Text("Nafl")
                } footer: {
                    Text("Voluntary prayers. These don't count towards streaks or reports.")
                }
            }
            .navigationTitle(day == today ? "Today" : day.shortTitle(in: model.timeZone))
            .navigationBarTitleDisplayMode(.inline)
            .messageAlert($gateMessage)
        }
    }
}
