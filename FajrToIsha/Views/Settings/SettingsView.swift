import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var showChangeLocation = false
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var infoMessage: String?

    var body: some View {
        @Bindable var settings = model.settings

        NavigationStack {
            Form {
                Section {
                    Picker("Reminder lead time", selection: $settings.reminderOffsetMins) {
                        ForEach(AppConfig.offsetOptions, id: \.self) { Text("\($0)m").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Reminder lead time")
                } footer: {
                    Text("How early the heads-up and the Fajr-ending warning arrive.")
                }

                Section("Asr calculation") {
                    Picker("Asr calculation", selection: $settings.asrSchool) {
                        Text("Hanafi").tag(1)
                        Text("Standard (Shafi'i)").tag(0)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Method", selection: $settings.calcMethod) {
                        ForEach(CalcMethod.all) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Calculation method")
                } footer: {
                    Text("The method strongly affects Fajr and Isha times. Default: Spiritual Administration of Muslims of Russia (14).")
                }

                Section("Location") {
                    LabeledContent("Location", value: model.settings.locationLabel)
                    LabeledContent("Timezone", value: model.settings.timezoneID ?? "—")
                    Button("Change Location") { showChangeLocation = true }
                }

                notificationsSection

                Section {
                    Button("Reset prayer logs", role: .destructive) { confirmReset = true }
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("Danger Zone")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: settings.reminderOffsetMins) { refreshAfterChange() }
            .onChange(of: settings.asrSchool) { refreshAfterChange() }
            .onChange(of: settings.calcMethod) { refreshAfterChange() }
            .task(id: scenePhase) { await loadNotificationState() }
            .sheet(isPresented: $showChangeLocation) {
                ChangeLocationSheet()
            }
            .alert("Reset prayer logs?", isPresented: $confirmReset) {
                Button("Yes, reset", role: .destructive) {
                    Task {
                        await model.resetPrayerLogs()
                        infoMessage = "Your prayer logs have been reset."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all your logged prayers. Your location and settings are kept. This cannot be undone.")
            }
            .alert("Delete all your data?", isPresented: $confirmDelete) {
                Button("Yes, delete everything", role: .destructive) { model.deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your account, location, settings, and every logged prayer, and stops all "
                     + "reminders. This cannot be undone.\n\nYou can set up the app again anytime.")
            }
            .alert("Done", isPresented: Binding(get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            LabeledContent("Permission", value: statusText)
            if notificationStatus == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            } else if notificationStatus == .notDetermined {
                Button("Enable notifications") {
                    Task {
                        await model.notifications.requestAuthorization()
                        await model.refresh()
                        await loadNotificationState()
                    }
                }
            }
            Button("Send test notification") {
                Task {
                    await model.notifications.sendTest()
                    infoMessage = notificationStatus == .denied
                        ? "Notifications are turned off for this app, so the test won't appear. Enable them in iOS Settings."
                        : "A test notification will arrive in about 5 seconds."
                }
            }
            LabeledContent("Scheduled alerts", value: "\(pendingCount)")
        } header: {
            Text("Notifications")
        } footer: {
            Text("Alerts are scheduled \(NotificationPlanner.windowDays) days ahead and refreshed whenever you open the app.")
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func loadNotificationState() async {
        notificationStatus = await model.notifications.authorizationStatus()
        pendingCount = await model.notifications.pendingCount()
    }

    private func refreshAfterChange() {
        Task {
            await model.refresh()
            await loadNotificationState()
        }
    }
}
