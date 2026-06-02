import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 18.0, *)
struct QuickFlagControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickFlagControl") {
            ControlWidgetButton(action: QuickFlagIntent()) {
                Label("Flag for Reply", systemImage: "flag.fill")
            }
        }
        .displayName("Flag for Reply")
        .description("Create a reply reminder")
    }
}
