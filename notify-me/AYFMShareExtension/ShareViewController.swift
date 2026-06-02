import UIKit
import UniformTypeIdentifiers

/// Share-sheet target: grabs a shared URL or text, records a compose request (as the
/// "Link" app, pre-filling the shared content), then opens AYFM straight into the
/// new-notification form. Shows no UI of its own.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedText { [weak self] text in
            // Record the request first so the app finds it even if `open` no-ops.
            ComposeHandoff.write(app: "Link", about: text)
            DispatchQueue.main.async { self?.openHostApp() }
        }
    }

    /// Pulls the first URL or plain-text attachment from the share, if any.
    private func extractSharedText(completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            completion(nil)
            return
        }

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if provider.hasItemConformingToTypeIdentifier(urlType) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { value, _ in
                completion((value as? URL)?.absoluteString ?? (value as? String))
            }
        } else if provider.hasItemConformingToTypeIdentifier(textType) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { value, _ in
                completion(value as? String)
            }
        } else {
            completion(nil)
        }
    }

    /// Opens AYFM via its custom URL scheme using the public extension-context API, then
    /// finishes. If `open` can't launch the app on some OS version, the request we already
    /// wrote to the App Group is picked up next time the user opens AYFM.
    private func openHostApp() {
        let finish: () -> Void = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
        guard let url = URL(string: "ayfm://compose") else { finish(); return }
        extensionContext?.open(url) { _ in finish() }
    }
}
