import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Query private var logs: [PrayerLog]
    @State private var gateMessage: String?
    @State private var upcoming: [(id: String, date: Date)] = []

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .navigationTitle("Today")
            .messageAlert($gateMessage)
            .refreshable { await model.refresh() }
            .task(id: upcomingKey) {
                upcoming = await model.notifications.pendingAlerts(on: model.today())
            }
        }
    }

    /// Re-query pending alerts when today's logs or the timings change.
    private var upcomingKey: String {
        let today = model.today().key
        let done = logs.filter { $0.day == today && $0.isCompleted }.map(\.prayerName).sorted()
        return "\(today)|\(done)|\(model.isRefreshing)"
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = model.today(now: now)
        let resolved = model.timings(for: today)
        let completed = Set(logs.filter { $0.category == LogCategory.fard.rawValue && $0.day == today.key && $0.isCompleted }
            .map(\.prayerName))
        let next = nextPrayer(after: now, today: today)

        List {
            Section {
                header(today: today, now: now, next: next, resolved: resolved)
            }

            Section {
                if let resolved {
                    TimingsList(timings: resolved.timings, highlighted: next?.day == today ? next?.name : nil)
                } else if model.isRefreshing {
                    ProgressView("Loading prayer times...")
                } else {
                    Text("Prayer times are unavailable. Pull to refresh when you're online.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Prayer times")
            } footer: {
                if resolved?.isFallback == true {
                    Text("Offline: showing the last prayer times that were downloaded.")
                } else {
                    Text("\(model.settings.locationLabel) · \(model.timeZone.identifier)")
                }
            }

            Section("Prayers") {
                ForEach(Prayers.fard, id: \.self) { name in
                    let adhan = model.adhan(name, on: today)
                    PrayerToggleRow(name: name, isCompleted: completed.contains(name),
                                    detail: adhan.map { TimeOfDay.format($0, in: model.timeZone) },
                                    isLocked: (adhan ?? .distantPast) > now) {
                        gateMessage = model.toggleFard(name, day: today, now: now).alertMessage
                    }
                }
            }

            Section("Upcoming alerts today") {
                let remaining = upcoming.filter { $0.date > now }
                if remaining.isEmpty {
                    Text("You have no upcoming prayer alerts scheduled for the rest of today.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remaining, id: \.id) { item in
                        LabeledContent(alertLabel(item.id), value: TimeOfDay.format(item.date, in: model.timeZone))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func header(today: Day, now: Date, next: (name: String, day: Day, date: Date)?,
                        resolved: ResolvedTimings?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(today.longTitle(in: model.timeZone))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let next {
                Text(next.day == today ? "Next: \(next.name)" : "Next: \(next.name) tomorrow")
                    .font(.title2.bold())
                Text(countdown(from: now, to: next.date))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Starts in \(countdown(from: now, to: next.date))")
                Text("Adhan at \(TimeOfDay.format(next.date, in: model.timeZone))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let resolved,
               let fajr = resolved.timings.date(of: "Fajr", on: today, in: resolved.timeZone),
               let sunrise = resolved.timings.date(of: "Sunrise", on: today, in: resolved.timeZone),
               fajr <= now, now < sunrise {
                Label("Fajr ends in \(countdown(from: now, to: sunrise))", systemImage: "sunrise")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.gold)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    private func nextPrayer(after now: Date, today: Day) -> (name: String, day: Day, date: Date)? {
        for name in Prayers.fard {
            if let date = model.adhan(name, on: today), date > now { return (name, today, date) }
        }
        let tomorrow = today.adding(days: 1)
        if let date = model.adhan("Fajr", on: tomorrow) { return ("Fajr", tomorrow, date) }
        return nil
    }

    private func countdown(from now: Date, to target: Date) -> String {
        let total = max(0, Int(target.timeIntervalSince(now)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Port of check_schedule_handler's labels.
    private func alertLabel(_ id: String) -> String {
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return id }
        if parts[1] == "summary" { return "End-of-day summary" }
        guard parts.count == 3 else { return id }
        switch (parts[1], parts[2]) {
        case ("Sunrise", "warning"): return "Fajr ending soon"
        case ("Sunrise", _): return "Fajr ends (sunrise)"
        case (let name, "warning"): return "\(name) warning"
        case (let name, _): return "\(name) adhan"
        }
    }
}
