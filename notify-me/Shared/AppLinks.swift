import Foundation

/// Maps a flagged reminder's source app to the URL scheme that launches it, so tapping
/// a reminder (or its notification) jumps straight into that app to reply.
///
/// We only have the app, not the specific conversation — apps don't expose a per-chat
/// link we can capture — so this opens the app to wherever it was last.
enum AppLinks {
    static let schemes: [String: String] = [
        "WhatsApp": "whatsapp://",
        "Telegram": "tg://",
        "Signal": "sgnl://",
        "Discord": "discord://",
        "Instagram": "instagram://",
        "Messenger": "fb-messenger://",
        "Snapchat": "snapchat://",
        "Slack": "slack://open",
        "Teams": "msteams://",
        "X": "twitter://",
        "TikTok": "tiktok://",
        "Reddit": "reddit://",
        "LinkedIn": "linkedin://",
        "Gmail": "googlegmail://",
        "Hinge": "hinge://",
        "Bumble": "bumble://",
        "Tinder": "tinder://",
        "Marketplace": "fb://",
        "iMessage": "messages://",
        "Mail": "message://",
    ]

    static func url(for sourceApp: String?) -> URL? {
        guard let sourceApp,
              let scheme = schemes[sourceApp] else { return nil }
        return URL(string: scheme)
    }
}
