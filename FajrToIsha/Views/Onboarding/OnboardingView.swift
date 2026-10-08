import SwiftUI

/// Replaces /start: welcome, location, timings, notification permission.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private enum Step: Equatable {
        case welcome
        case location
        case result(ResolvedTimings)
        case notifications
    }

    @State private var step: Step = .welcome
    @State private var isFinishing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch step {
                case .welcome: welcome
                case .location: location
                case let .result(resolved): result(resolved)
                case .notifications: notifications
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .animation(.default, value: step)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 48)
            Text("Assalamu alaykum")
                .font(.largeTitle.bold())
            Text("Fajr to Isha shows accurate prayer times for where you are, reminds you before "
                 + "and at each adhan, and helps you build a consistent prayer habit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Everything stays on this device. No account needed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                step = .location
            } label: {
                Text("Get started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top)
        }
    }

    private var location: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 32)
            Text("Your location")
                .font(.title.bold())
            Text("To calculate prayer times and send reminders on time, the app needs your location "
                 + "and timezone. Your location is only sent to the Aladhan prayer times service.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            LocationSetupView { resolved in step = .result(resolved) }
        }
    }

    private func result(_ resolved: ResolvedTimings) -> some View {
        VStack(spacing: 20) {
            LocationResultView(resolved: resolved)
                .padding(.top, 32)
            Button {
                step = .notifications
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Use a different location") { step = .location }
        }
    }

    private var notifications: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 32)
            Text("Prayer reminders")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 10) {
                Label("A heads-up \(model.settings.reminderOffsetMins) minutes before each prayer", systemImage: "clock")
                Label("An alert at the adhan with “Mark as Prayed”", systemImage: "speaker.wave.2")
                Label("A warning before Fajr time ends at sunrise", systemImage: "sunrise")
                Label("An end-of-day summary at \(TimeOfDay.format(String(format: "%02d:00", AppConfig.summaryHour)))",
                      systemImage: "moon")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await finish(requestNotifications: true) }
            } label: {
                Text("Enable notifications").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isFinishing)
            Button("Not now") { Task { await finish(requestNotifications: false) } }
                .disabled(isFinishing)
            if isFinishing { ProgressView("Setting up your prayer alerts...") }
        }
    }

    private func finish(requestNotifications: Bool) async {
        isFinishing = true
        if requestNotifications { await model.notifications.requestAuthorization() }
        model.settings.hasOnboarded = true
        await model.refresh()
        isFinishing = false
    }
}
