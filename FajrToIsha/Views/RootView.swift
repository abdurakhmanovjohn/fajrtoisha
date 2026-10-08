import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.settings.hasOnboarded {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            LogView()
                .tabItem { Label("Log", systemImage: "checklist") }
                .tag(AppTab.log)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(AppTab.stats)
            QazaView()
                .tabItem { Label("Qaza", systemImage: "arrow.uturn.backward.circle") }
                .tag(AppTab.qaza)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

/// Shared alert text for toggle outcomes (the bot's show_alert answers).
extension LogStore.ToggleResult {
    var alertMessage: String? {
        switch self {
        case .changed: nil
        case let .notTimeYet(prayer, adhan): "It is not time for \(prayer) yet. Adhan is at \(adhan)."
        case .futureDate: "You cannot log prayers for future dates."
        }
    }
}

extension View {
    /// Presents a simple OK alert while `message` is non-nil.
    func messageAlert(_ message: Binding<String?>) -> some View {
        alert("Not yet", isPresented: Binding(get: { message.wrappedValue != nil },
                                              set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
