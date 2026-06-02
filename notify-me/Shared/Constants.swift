import Foundation

enum AppConstants {
    static let pendingDirectory = "PendingReminders"
    static let notificationCategoryID = "REMINDER_CATEGORY"
    static let markAnsweredActionID = "MARK_ANSWERED_ACTION"
    static let snoozeActionID = "SNOOZE_ACTION"
    static let defaultIntervalKey = "defaultIntervalMinutes"   // the global fallback interval
    static let appIntervalsKey = "appSpecificIntervals"        // per-app interval overrides
    static let selectedPlatformsKey = "selectedPlatforms"
    static let customPlatformsKey = "customPlatforms"          // user-added apps (persist independently of slots)
    static let widgetPageKey = "quickFlagWidgetPage"
    static let widgetFlashAppKey = "quickFlagFlashApp"
    static let widgetFlashDateKey = "quickFlagFlashDate"
    static let composeAppKey = "composeReminderApp"
    static let composeDateKey = "composeReminderDate"

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

/// Robust hand-off of "open the compose form for this app" from the widget (a separate
/// process) to the app. We write it as an atomic file in the shared container rather than
/// to UserDefaults: cross-process UserDefaults reads can return a stale, per-process
/// cached value, which made the tapped app sometimes arrive wrong or missing. A file is
/// read fresh from disk every time, so the app always sees exactly what the widget wrote.
enum ComposeHandoff {
    struct Request: Codable {
        let app: String?
        let date: Date
    }

    private static var fileURL: URL {
        AppConstants.sharedContainerURL.appendingPathComponent("compose-request.json")
    }

    /// Records a request to compose for `app` (nil = no specific app).
    static func write(app: String?) {
        guard let data = try? JSONEncoder().encode(Request(app: app, date: Date())) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Returns and clears a pending request, if one was written within `maxAge` seconds.
    static func consume(maxAge: TimeInterval = 15) -> Request? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        guard let request = try? JSONDecoder().decode(Request.self, from: data),
              Date().timeIntervalSince(request.date) < maxAge else { return nil }
        return request
    }
}
