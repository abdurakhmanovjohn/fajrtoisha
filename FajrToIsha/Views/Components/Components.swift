import SwiftUI

/// A prayer row with a check toggle (replaces the bot's ✅ / ▫️ buttons).
struct PrayerToggleRow: View {
    let name: String
    let isCompleted: Bool
    var detail: String?
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isCompleted)
        .accessibilityAddTraits(isCompleted ? .isSelected : [])
        .accessibilityHint(isCompleted ? "Logged. Tap to unmark." : "Tap to log.")
    }
}

/// ‹ Prev / Today / Next › plus a date picker. Future dates are locked.
struct DayNavigator: View {
    @Binding var day: Day
    let today: Day
    let timeZone: TimeZone

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = AppConfig.firstWeekday
        return cal
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { day = day.adding(days: -1) } label: {
                    Label("Prev", systemImage: "chevron.left")
                }
                Spacer()
                Button("Today") { day = today }
                    .disabled(day == today)
                Spacer()
                Button { day = day.adding(days: 1) } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .disabled(day >= today)
            }
            .buttonStyle(.bordered)

            DatePicker("Date", selection: dateBinding, in: ...today.startDate(in: timeZone),
                       displayedComponents: .date)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, timeZone)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { day.startDate(in: timeZone) },
            set: { day = min(Day($0, in: timeZone), today) }
        )
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// The six daily timings, with one optionally highlighted.
struct TimingsList: View {
    let timings: DayTimings
    var highlighted: String?

    var body: some View {
        ForEach(Prayers.timingNames, id: \.self) { name in
            HStack {
                Image(systemName: icon(for: name))
                    .frame(width: 24)
                    .foregroundStyle(name == highlighted ? Color.accentColor : .secondary)
                Text(name)
                    .fontWeight(name == highlighted ? .semibold : .regular)
                Spacer()
                Text(TimeOfDay.format(timings[name] ?? "--:--"))
                    .font(.body.monospacedDigit())
                    .fontWeight(name == highlighted ? .semibold : .regular)
            }
            .foregroundStyle(name == "Sunrise" && name != highlighted ? .secondary : .primary)
            .listRowBackground(name == highlighted ? Color.accentColor.opacity(0.12) : nil)
        }
    }

    private func icon(for name: String) -> String {
        switch name {
        case "Fajr": "sun.haze"
        case "Sunrise": "sunrise"
        case "Dhuhr": "sun.max"
        case "Asr": "sun.min"
        case "Maghrib": "sunset"
        default: "moon.stars"
        }
    }
}

extension Day {
    /// e.g. "Thursday, 8 October 2026"
    func longTitle(in timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return f.string(from: startDate(in: timeZone))
    }

    /// e.g. "8 Oct"
    func shortTitle(in timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: startDate(in: timeZone))
    }
}
