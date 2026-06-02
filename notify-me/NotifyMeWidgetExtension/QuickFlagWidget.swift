import WidgetKit
import SwiftUI
import AppIntents
import UIKit

struct QuickFlagWidget: Widget {
    let kind = "QuickFlagWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickFlagTimelineProvider()) { entry in
            QuickFlagWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Flag")
        .description("Flag messages for reply reminders")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickFlagEntry: TimelineEntry {
    let date: Date
}

struct QuickFlagTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickFlagEntry {
        QuickFlagEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickFlagEntry) -> Void) {
        completion(QuickFlagEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickFlagEntry>) -> Void) {
        completion(Timeline(entries: [QuickFlagEntry(date: .now)], policy: .never))
    }
}

struct QuickFlagWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuickFlagEntry

    // The user's chosen platforms, configured in the app and shared via the App Group.
    // iMessage/Mail are handled automatically elsewhere, so they aren't listed here.
    private var platforms: [FlagPlatform] { PlatformStore.load() }

    var body: some View {
        if family == .systemSmall {
            Button(intent: QuickFlagIntent()) {
                Label("Flag for Reply", systemImage: "flag.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(.orange)
            .padding(8)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 76), spacing: 6)],
                spacing: 6
            ) {
                ForEach(platforms) { platform in
                    Button(intent: QuickFlagIntent(sourceApp: platform.name)) {
                        VStack(spacing: 3) {
                            platformIcon(platform)
                            Text(platform.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(.blue)
                }
            }
            .padding(8)
        }
    }

    /// Official app icon if the app has cached it, otherwise the SF Symbol fallback.
    @ViewBuilder
    private func platformIcon(_ platform: FlagPlatform) -> some View {
        if let data = AppIconStore.cachedData(for: platform.name),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: platform.icon)
                .font(.system(size: 18))
                .frame(width: 26, height: 26)
        }
    }
}
