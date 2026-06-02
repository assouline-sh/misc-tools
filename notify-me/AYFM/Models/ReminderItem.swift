import Foundation
import SwiftData

@Model
final class ReminderItem {
    @Attribute(.unique) var id: UUID
    var messageText: String
    var senderName: String?
    var sourceApp: String?
    var createdAt: Date
    var answeredAt: Date?
    var isAnswered: Bool
    var notificationIntervalMinutes: Int

    init(
        id: UUID = UUID(),
        messageText: String,
        senderName: String? = nil,
        sourceApp: String? = nil,
        intervalMinutes: Int = 60
    ) {
        self.id = id
        self.messageText = messageText
        self.senderName = senderName
        self.sourceApp = sourceApp
        self.createdAt = Date()
        self.answeredAt = nil
        self.isAnswered = false
        self.notificationIntervalMinutes = intervalMinutes
    }

    convenience init(from pending: PendingReminder) {
        self.init(
            id: pending.id,
            messageText: pending.messageText,
            senderName: pending.senderName,
            sourceApp: pending.sourceApp,
            intervalMinutes: pending.intervalMinutes
        )
        self.createdAt = pending.createdAt
    }
}
