import AppIntents
import WidgetKit

/// Pages the small Quick Flag widget forward or backward through the user's apps,
/// wrapping around at either end. Page state lives in the shared App Group so the
/// widget view reads the same value the intent just wrote.
struct QuickFlagPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Change page"
    static var description: IntentDescription = "Show another set of apps"
    static var openAppWhenRun: Bool = false

    /// Number of apps shown per page in the small (square) widget.
    static let pageSize = 4

    @Parameter(title: "Forward")
    var forward: Bool

    init() { self.forward = true }

    init(forward: Bool) { self.forward = forward }

    func perform() async throws -> some IntentResult {
        let count = PlatformStore.load().count
        let pageCount = max(1, Int(ceil(Double(count) / Double(Self.pageSize))))

        let current = AppConstants.sharedDefaults.integer(forKey: AppConstants.widgetPageKey)
        // +pageCount keeps the result non-negative when paging backward from page 0.
        let next = (current + (forward ? 1 : -1) + pageCount) % pageCount
        AppConstants.sharedDefaults.set(next, forKey: AppConstants.widgetPageKey)

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
