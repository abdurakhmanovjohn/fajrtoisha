import SwiftUI
import SwiftData

@main
struct FajrToIshaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.refresh() }
            case .background: model.scheduleBackgroundRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppConfig.backgroundRefreshID)) {
            await AppModel.shared.refresh()
        }
    }
}
