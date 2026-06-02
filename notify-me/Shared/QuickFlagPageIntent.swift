import AppIntents
import WidgetKit

/// Pages the small Quick Flag widget forward or backward through the user's apps,
/// wrapping around at either end. Page state lives in the shared App Group so the
/// widget view reads the same value the intent just wrote.
struct QuickFlagPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Change page"
    static var description: IntentDescription = "Show another set of apps"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Forward")
    var forward: Bool

    /// Apps per page for the widget family this button lives in (square = 4, medium = 10).
    /// Passed in so the page math matches what the view actually shows; a fixed size here
    /// made the medium widget's arrow skip/stick on the last page.
    @Parameter(title: "Page size")
    var pageSize: Int

    init() { self.forward = true; self.pageSize = 4 }

    init(forward: Bool, pageSize: Int) { self.forward = forward; self.pageSize = pageSize }

    func perform() async throws -> some IntentResult {
        let size = max(1, pageSize)
        let count = PlatformStore.load().count
        let pageCount = max(1, Int(ceil(Double(count) / Double(size))))

        let current = AppConstants.sharedDefaults.integer(forKey: AppConstants.widgetPageKey)
        // +pageCount keeps the result non-negative when paging backward from page 0.
        let next = (current + (forward ? 1 : -1) + pageCount) % pageCount
        AppConstants.sharedDefaults.set(next, forKey: AppConstants.widgetPageKey)

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
