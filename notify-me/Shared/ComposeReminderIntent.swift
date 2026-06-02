import Foundation
import AppIntents

/// Tapping an app in the widget runs this: it opens AYFM and records which app was
/// tapped (via `ComposeHandoff`, an atomic file in the shared App Group) so the app can
/// present a pre-filled "new reminder" form. It creates nothing on its own — the form
/// does that on save.
struct ComposeReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Reply Reminder"
    static var description = IntentDescription("Open AYFM to fill in reply details")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Source App")
    var sourceApp: String?

    init() {}

    init(sourceApp: String) {
        self.sourceApp = sourceApp
    }

    func perform() async throws -> some IntentResult {
        ComposeHandoff.write(app: sourceApp)
        return .result()
    }
}
