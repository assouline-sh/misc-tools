import AppIntents

/// Surfaces the auto-flag intent as a ready-made App Shortcut and Siri phrases, so it's
/// easy to find in the Shortcuts app and can be triggered by voice. The Messages/Mail
/// Personal Automations the user sets up call `CreateReminderIntent` directly — this just
/// aids discovery and gives a hands-free entry point.
struct AYFMShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Track a reply in \(.applicationName)",
                "Remind me to reply in \(.applicationName)",
                "\(.applicationName) remind me to reply"
            ],
            shortTitle: "Track a Reply",
            systemImageName: "bell.badge"
        )
    }
}
