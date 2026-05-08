import SwiftUI
import SwiftData

@main
struct NotifyMeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        let schema = Schema([ReminderItem.self])
        let storeURL = AppConstants.sharedContainerURL
            .appendingPathComponent("NotifyMe.store")
        let config = ModelConfiguration(url: storeURL)
        container = try! ModelContainer(for: schema, configurations: [config])

        NotificationManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    Task {
                        _ = await NotificationManager.shared.requestAuthorization()
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let context = container.mainContext
                SharedDataManager.importPendingReminders(context: context)
                SharedDataManager.rescheduleAll(context: context)
            }
        }
    }
}
