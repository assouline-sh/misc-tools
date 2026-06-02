import SwiftUI
import UIKit

struct ReminderRow: View {
    let item: ReminderItem
    @ObservedObject private var icons = AppIconCache.shared

    var body: some View {
        HStack(spacing: 12) {
            logo

            VStack(alignment: .leading, spacing: 2) {
                if let sender = item.senderName, !sender.isEmpty {
                    Text(sender).foregroundStyle(textColor)
                }
                if let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.ageLabel(age))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Text("bothered you \(nagCount)×")
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder private var logo: some View {
        if let image = icons.images[appName] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Text(fallbackName)
                .font(.headline)
                .textCase(.lowercase)
                .foregroundStyle(textColor)
        }
    }

    @ViewBuilder private var background: some View {
        let gradient = icons.gradients[appName] ?? []
        if gradient.count >= 2 {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if Theme.hasBrand(for: item.sourceApp) {
            Theme.brand(for: item.sourceApp)
        } else {
            // No logo and no known brand colour — a gray sweep instead of the amber accent,
            // which would otherwise blend with the "answered" reveal.
            LinearGradient(colors: Theme.neutralGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var appName: String { item.sourceApp ?? "" }

    private var textColor: Color { icons.textColors[appName] ?? .white }

    private var fallbackName: String {
        if let app = item.sourceApp, !app.isEmpty { return app }
        if let sender = item.senderName, !sender.isEmpty { return sender }
        return "message"
    }

    /// Only show the message body when it's real content (not an auto-generated stamp).
    private var preview: String? {
        item.messageText.hasPrefix("Flagged at") ? nil : item.messageText
    }

    private var age: TimeInterval {
        Date().timeIntervalSince(item.createdAt)
    }

    /// How many times the repeating notification has nagged you so far. Time spent under a
    /// global "pause all" is excluded — nothing fires while paused, so it shouldn't count.
    private var nagCount: Int {
        let interval = TimeInterval(item.notificationIntervalMinutes * 60)
        guard interval > 0 else { return 0 }
        let paused = SnoozeStore.pausedSeconds(from: item.createdAt, to: Date())
        return max(0, Int((age - paused) / interval))
    }
}
