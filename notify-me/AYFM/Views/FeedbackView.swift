import SwiftUI
import MessageUI
import UIKit

/// Lets the user send one piece of feedback (≤500 chars) per 24 hours. The text is sent
/// as an email to the developer via the system Mail composer (or a mailto: fallback).
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var showingMail = false

    private let limit = 500
    private let recipient = "ayfm.feedback@proton.me"
    private let subject = "AYFM Feedback"

    /// When the last feedback was sent, if ever.
    private var lastSent: Date? {
        let t = AppConstants.sharedDefaults.double(forKey: AppConstants.lastFeedbackDateKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Feedback is allowed once every 24 hours.
    private var canSend: Bool {
        guard let lastSent else { return true }
        return Date().timeIntervalSince(lastSent) >= 24 * 3600
    }

    /// Whole hours until feedback is allowed again.
    private var hoursUntilAllowed: Int {
        guard let lastSent else { return 0 }
        let remaining = 24 * 3600 - Date().timeIntervalSince(lastSent)
        return max(1, Int(ceil(remaining / 3600)))
    }

    /// Sanitized outgoing text: stray control characters removed (newlines kept), capped
    /// to the limit, and trimmed.
    private var sanitized: String {
        let stripControls = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\n"))
        return String(text.prefix(limit))
            .components(separatedBy: stripControls)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .disabled(!canSend)
                    .onChange(of: text) { _, value in
                        if value.count > limit { text = String(value.prefix(limit)) }
                    }

                HStack {
                    if !canSend {
                        Text("come back in \(hoursUntilAllowed)h — one per day")
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Text("\(text.count)/\(limit)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("feedback")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("send", action: send)
                    .fontWeight(.bold)
                    .disabled(sanitized.isEmpty || !canSend)
            }
        }
        .sheet(isPresented: $showingMail) {
            MailComposeView(recipient: recipient, subject: subject, body: sanitized) { result in
                if result == .sent { markSent() }
            }
        }
    }

    private func send() {
        guard canSend, !sanitized.isEmpty else { return }
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else if let url = mailtoURL() {
            // No Mail account configured — hand off to whatever handles mailto:, and
            // count it as sent since we can't observe the result.
            UIApplication.shared.open(url)
            markSent()
            dismiss()
        }
    }

    private func markSent() {
        AppConstants.sharedDefaults.set(Date().timeIntervalSince1970, forKey: AppConstants.lastFeedbackDateKey)
        dismiss()
    }

    private func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: sanitized),
        ]
        return components.url
    }
}

/// Wraps the system Mail composer so feedback can be emailed without leaving the app.
private struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onResult: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onResult: (MFMailComposeResult) -> Void
        init(onResult: @escaping (MFMailComposeResult) -> Void) { self.onResult = onResult }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onResult(result)
            controller.dismiss(animated: true)
        }
    }
}
