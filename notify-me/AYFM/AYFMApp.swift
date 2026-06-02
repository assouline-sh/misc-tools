import SwiftUI
import SwiftData
import UIKit

@main
struct AYFMApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        container = Self.makeContainer()

        // Let notification actions (e.g. "Mark as Answered") write through the same live
        // container the UI observes, so changes show up without a relaunch.
        NotificationManager.shared.modelContainer = container
        NotificationManager.shared.setup()
        IntervalStore.sanitize()   // clear out retired interval values (e.g. the old 1-min default)
        SnoozeStore.clearExpiredSnooze()   // tidy up a finished "pause all" timestamp
        Self.configureNavigationBarFont()
    }

    /// Open the SwiftData store, recovering instead of crashing if it can't be loaded
    /// (corruption or a failed migration). A force-`try!` here would brick the app on every
    /// launch; instead we move the unreadable store aside and start fresh, falling back to an
    /// in-memory store as a last resort so the app still opens.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([ReminderItem.self])
        let storeURL = AppConstants.sharedContainerURL.appendingPathComponent("AYFM.store")
        let config = ModelConfiguration(url: storeURL)

        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        archiveUnreadableStore(at: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        // Last resort: keep the app usable for this session even with no on-disk store.
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memory])
    }

    /// Rename the store (and its SQLite sidecar files) aside so a fresh one can be created.
    /// The old files are preserved with a ".broken" suffix in case they're ever recoverable.
    private static func archiveUnreadableStore(at storeURL: URL) {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        for name in [base, base + "-shm", base + "-wal"] {
            let src = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent(name + ".broken")
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }
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
