import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct NotifyMeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotifyMeActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                Text("NotifyMe")
                    .font(.headline)
                Spacer()
                if context.state.activeReminderCount > 0 {
                    Text("\(context.state.activeReminderCount) flagged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text("Flag for Reply")
                            .font(.headline)
                        if let lastApp = context.state.lastFlaggedApp,
                           let lastTime = context.state.lastFlaggedTime {
                            Text("\(lastApp) at \(lastTime, style: .time)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Button(intent: QuickFlagIntent()) {
                            Label("Flag", systemImage: "flag.fill")
                                .font(.caption)
                        }
                        .tint(.orange)

                        Button(intent: QuickFlagIntent(sourceApp: "iMessage")) {
                            Text("iMsg").font(.caption2)
                        }
                        .tint(.blue)

                        Button(intent: QuickFlagIntent(sourceApp: "Telegram")) {
                            Text("TG").font(.caption2)
                        }
                        .tint(.blue)

                        Button(intent: QuickFlagIntent(sourceApp: "Signal")) {
                            Text("Sig").font(.caption2)
                        }
                        .tint(.blue)

                        Button(intent: QuickFlagIntent(sourceApp: "Discord")) {
                            Text("DC").font(.caption2)
                        }
                        .tint(.blue)

                        Button(intent: QuickFlagIntent(sourceApp: "WhatsApp")) {
                            Text("WA").font(.caption2)
                        }
                        .tint(.blue)
                    }
                }
            } compactLeading: {
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
            } compactTrailing: {
                if context.state.activeReminderCount > 0 {
                    Text("\(context.state.activeReminderCount)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            } minimal: {
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}
