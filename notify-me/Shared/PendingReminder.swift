import Foundation

struct PendingReminder: Codable {
    let id: UUID
    let messageText: String
    let senderName: String?
    let sourceApp: String?
    let createdAt: Date
    let intervalMinutes: Int

    func write() throws {
        let url = AppConstants.pendingRemindersURL
            .appendingPathComponent("\(id.uuidString).json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func loadAll() -> [PendingReminder] {
        let url = AppConstants.pendingRemindersURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }

        return files.compactMap { fileURL in
            guard fileURL.pathExtension == "json",
                  let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? JSONDecoder().decode(PendingReminder.self, from: data)
        }
    }

    static func delete(id: UUID) {
        let url = AppConstants.pendingRemindersURL
            .appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}

/// Builds the user-facing text for a reminder's notification, shared across every place
/// that schedules one so they read consistently.
enum ReminderNotification {
    /// - With a name: "Answer <name> on <app>" (drops " on <app>" if no app).
    /// - Without a name: "Answer message(s) from <app>" (or "Answer your messages").
    /// - If an "about" was given it's the (bold) subtitle; otherwise a regular-weight
    ///   "flagged …" line goes in the body so it doesn't render bold.
    static func text(senderName: String?, sourceApp: String?, messageText: String?, createdAt: Date)
        -> (title: String, subtitle: String?, body: String?)
    {
        let name = senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !(name?.isEmpty ?? true)
        let hasApp = !(app?.isEmpty ?? true)

        let title: String
        switch (hasName, hasApp) {
        case (true, true):   title = "Answer \(name!) on \(app!)"
        case (true, false):  title = "Answer \(name!)"
        case (false, true):  title = "Answer message(s) from \(app!)"
        case (false, false): title = "Answer your messages"
        }

        if let about = about(messageText) {
            return (title, about, nil)
        } else {
            return (title, nil, flaggedText(createdAt))
        }
    }

    /// Groups notifications in Notification Center per source app. Reminders with no app
    /// fall into a single "ungrouped" thread so they don't each form their own group.
    static func threadIdentifier(sourceApp: String?) -> String {
        let app = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app, !app.isEmpty else { return "reminders-no-app" }
        return "reminders-app-\(app.lowercased())"
    }

    /// The real "about" text, or nil if it's empty or just the auto-generated flag stamp.
    static func about(_ messageText: String?) -> String? {
        guard let text = messageText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("Flagged at") else { return nil }
        return text
    }

    /// "flagged at <time>" if flagged today, otherwise "flagged <n> day(s) ago".
    static func flaggedText(_ createdAt: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: createdAt),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0

        if days <= 0 {
            return "from \(timeFormatter.string(from: createdAt))"
        }
        return "from \(days) day\(days == 1 ? "" : "s") ago"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
