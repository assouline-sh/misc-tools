import AppIntents

struct NotifyMeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Remind me to reply in \(.applicationName)",
                "Create a reminder in \(.applicationName)",
                "\(.applicationName) remind me to reply"
            ],
            shortTitle: "Remind Me to Reply",
            systemImageName: "bell.badge"
        )
    }
}
