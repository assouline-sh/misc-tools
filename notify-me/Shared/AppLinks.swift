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
        "Facebook": "fb://",
        "Threads": "barcelona://",
        "WeChat": "weixin://",
        "Line": "line://",
        "Viber": "viber://",
        "KakaoTalk": "kakaotalk://",
        "Mastodon": "mastodon://",
        "BeReal": "bereal://",
        "Twitch": "twitch://",
        "YouTube": "youtube://",
        "Pinterest": "pinterest://",
        "Outlook": "ms-outlook://",
        "Tumblr": "tumblr://",
        "Hinge": "hinge://",
        "Bumble": "bumble://",
        "Tinder": "tinder://",
        "Grindr": "grindr://",
        "eBay": "ebay://",
        "Etsy": "etsy://",
        "Depop": "depop://",
        "Airbnb": "airbnb://",
        "Venmo": "venmo://",
        "PayPal": "paypal://",
        "iMessage": "messages://",
        // Apple's Messages opens to the most recent thread via the SMS scheme; "Mail" uses
        // Mail's (private but long-stable) message scheme. These back the auto-flag sources.
        "Messages": "sms:",
        "Mail": "message://",
    ]

    static func url(for sourceApp: String?) -> URL? {
        guard let sourceApp,
              let scheme = schemes[sourceApp] else { return nil }
        return URL(string: scheme)
    }
}
