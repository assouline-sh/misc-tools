import Foundation

enum AppConstants {
    static let pendingDirectory = "PendingReminders"
    static let notificationCategoryID = "REMINDER_CATEGORY"
    static let markAnsweredActionID = "MARK_ANSWERED_ACTION"
    static let snoozeActionID = "SNOOZE_ACTION"
    static let defaultIntervalKey = "defaultIntervalMinutes"
    static let selectedPlatformsKey = "selectedPlatforms"

    /// App Group shared between the app, share extension, and widget extension.
    /// Must match the `com.apple.security.application-groups` entitlement in all three targets.
    static let appGroupID = "group.kud.remindreply"

    /// Container shared across all targets via the App Group. The reminder hand-off
    /// files and the SwiftData store live here so every process sees the same data.
    static var sharedContainerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// UserDefaults shared across all targets. Settings written in the app (e.g. the
    /// default interval) are read by the intents/extensions running in other processes.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var pendingRemindersURL: URL {
        let url = sharedContainerURL.appendingPathComponent(pendingDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
