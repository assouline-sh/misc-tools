import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<NotifyMeActivityAttributes>?

    private init() {}

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Reattach to an existing activity if one is still running
        if let existing = Activity<NotifyMeActivityAttributes>.activities.first {
            currentActivity = existing
            return
        }

        let attributes = NotifyMeActivityAttributes()
        let initialState = NotifyMeActivityAttributes.ContentState(
            activeReminderCount: 0,
            lastFlaggedApp: nil,
            lastFlaggedTime: nil
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Live Activities not available
        }
    }

    func incrementCount(lastApp: String?) async {
        guard let activity = currentActivity ?? Activity<NotifyMeActivityAttributes>.activities.first else { return }
        let current = activity.content.state.activeReminderCount
        let newState = NotifyMeActivityAttributes.ContentState(
            activeReminderCount: current + 1,
            lastFlaggedApp: lastApp,
            lastFlaggedTime: Date()
        )
        await activity.update(.init(state: newState, staleDate: nil))
    }

    func updateCount(_ count: Int) async {
        guard let activity = currentActivity ?? Activity<NotifyMeActivityAttributes>.activities.first else { return }
        let newState = NotifyMeActivityAttributes.ContentState(
            activeReminderCount: count,
            lastFlaggedApp: nil,
            lastFlaggedTime: nil
        )
        await activity.update(.init(state: newState, staleDate: nil))
    }

    func stop() async {
        await currentActivity?.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
    }
}
