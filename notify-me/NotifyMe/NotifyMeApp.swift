import SwiftUI
import SwiftData
import UIKit

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
        Self.configureNavigationBarFont()
    }

    /// Force navigation-bar titles and buttons to the same monospaced family the rest of
    /// the app uses (UIKit nav bars ignore SwiftUI's `.fontDesign(.monospaced)`).
    private static func configureNavigationBarFont() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.shadowColor = .clear

        let titleColor = UIColor(Theme.text)
        appearance.titleTextAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .bold),
            .foregroundColor: titleColor,
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .bold),
            .foregroundColor: titleColor,
        ]

        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
            .foregroundColor: UIColor(Theme.accent),
        ]
        appearance.buttonAppearance = buttons
        appearance.doneButtonAppearance = buttons
        appearance.backButtonAppearance = buttons

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
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
