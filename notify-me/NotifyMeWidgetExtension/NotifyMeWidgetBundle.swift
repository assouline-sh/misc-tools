import WidgetKit
import SwiftUI

@main
struct AYFMWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickFlagWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            QuickFlagControl()
        }
    }
}
