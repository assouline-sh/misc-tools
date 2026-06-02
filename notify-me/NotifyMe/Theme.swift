import SwiftUI
import UIKit

/// AYFM — "Terminal" theme. A deadpan, no-BS system-utility look: near-black surfaces,
/// monospace type, hairline-bordered panels, a green prompt accent with amber/red for
/// how late you are. Forced dark; warmth is not the point.
enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.051)  // #0B0B0D
    static let surface    = Color(red: 0.086, green: 0.086, blue: 0.098)  // #16161A
    static let card       = surface
    static let text       = Color(red: 0.902, green: 0.902, blue: 0.902)  // #E6E6E6
    static let dim        = Color(red: 0.470, green: 0.470, blue: 0.500)   // #787880
    static let accent     = Color(red: 0.212, green: 0.827, blue: 0.600)   // #36D399 green
    static let warn       = Color(red: 0.961, green: 0.651, blue: 0.137)   // #F5A623 amber
    static let late       = Color(red: 0.878, green: 0.141, blue: 0.106)   // #E0241B red
    static let border     = Color(red: 0.157, green: 0.157, blue: 0.176)   // #28282D

    /// Urgency color for how long a message has gone unanswered.
    static func urgency(forSeconds seconds: TimeInterval) -> Color {
        if seconds >= 12 * 3_600 { return late }   // 12 hours or more
        if seconds >= 3_600 { return warn }        // an hour or more
        return accent
    }

    /// Coarse age label: under an hour, under 12 hours, otherwise whole days.
    static func ageLabel(_ seconds: TimeInterval) -> String {
        if seconds < 3_600 { return "< 1 hour" }
        if seconds < 12 * 3_600 { return "< 12 hours" }
        let days = max(1, Int((seconds / 86_400).rounded()))
        return days == 1 ? "1 day" : "\(days) days"
    }
}

extension Theme {
    /// Each app's recognizable brand color, used to tint its row. Falls back to the
    /// green accent for custom/unknown apps. Approximations — Apple ships no brand assets.
    static let brandColors: [String: Color] = [
        "WhatsApp": Color(hex: 0x25D366),
        "Telegram": Color(hex: 0x229ED9),
        "Signal": Color(hex: 0x3A76F0),
        "Discord": Color(hex: 0x5865F2),
        "Instagram": Color(hex: 0xE1306C),
        "Messenger": Color(hex: 0x0084FF),
        "Snapchat": Color(hex: 0xFFFC00),
        "Slack": Color(hex: 0x611F69),
        "Teams": Color(hex: 0x6264A7),
        "X": Color(hex: 0x1DA1F2),
        "TikTok": Color(hex: 0xEE1D52),
        "Reddit": Color(hex: 0xFF4500),
        "LinkedIn": Color(hex: 0x0A66C2),
        "Gmail": Color(hex: 0xEA4335),
        "Hinge": Color(hex: 0x782E8E),
        "Bumble": Color(hex: 0xFFC629),
        "Tinder": Color(hex: 0xFD5068),
        "Marketplace": Color(hex: 0x1877F2),
        "iMessage": Color(hex: 0x0A84FF),
        "Mail": Color(hex: 0x2D7DF6),
    ]

    static func brand(for sourceApp: String?) -> Color {
        guard let sourceApp else { return accent }
        return brandColors[sourceApp] ?? accent
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Full-screen dark backdrop behind a scrollable container.
    func screen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// A flat, hairline-bordered panel — the only "card" in a terminal.
    func panel(cornerRadius: CGFloat = 6) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}
