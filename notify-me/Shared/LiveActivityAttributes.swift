import ActivityKit
import Foundation

struct NotifyMeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var activeReminderCount: Int
        var lastFlaggedApp: String?
        var lastFlaggedTime: Date?
    }
}
