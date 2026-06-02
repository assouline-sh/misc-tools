import SwiftUI
import WidgetKit
import UIKit

/// Fetches official app icons from Apple's public iTunes Search API, caches them to the
/// shared App Group, and derives each icon's gradient + a legible text color by sampling
/// its pixels. Shared singleton so every screen reuses the same in-memory art.
/// Nothing copyrighted is bundled — icons live only on-device, loaded from Apple's CDN.
@MainActor
final class AppIconCache: ObservableObject {
    static let shared = AppIconCache()

    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var gradients: [String: [Color]] = [:]
    @Published private(set) var textColors: [String: Color] = [:]

    /// Load any already-downloaded icons from disk (synchronous, fast).
    func loadCached(_ platforms: [FlagPlatform]) {
        for platform in platforms where images[platform.name] == nil {
            if let data = AppIconStore.cachedData(for: platform.name),
               let image = UIImage(data: data) {
                store(image, for: platform.name)
            }
        }
    }

    /// Download any icons not yet cached.
    func fetchMissing(_ platforms: [FlagPlatform]) {
        for platform in platforms where images[platform.name] == nil {
            let term = AppIconStore.searchTerm(for: platform.name)
            guard !term.isEmpty else { continue }
            Task { await fetch(name: platform.name, term: term) }
        }
    }

    private func store(_ image: UIImage, for name: String) {
        images[name] = image
        let art = Self.extractArt(from: image)
        gradients[name] = art.gradient
        textColors[name] = art.text
    }

    private func fetch(name: String, term: String) async {
        guard let searchURL = searchURL(term: term) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: searchURL)
            guard let artworkURL = parseArtworkURL(data) else { return }
            let (imageData, _) = try await URLSession.shared.data(from: artworkURL)
            guard let image = UIImage(data: imageData) else { return }

            try? imageData.write(to: AppIconStore.fileURL(for: name), options: .atomic)
            store(image, for: name)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Offline or lookup failed — the caller's fallback (brand color) stays.
        }
    }

    private func searchURL(term: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: "us"),
        ]
        return components?.url
    }

    private func parseArtworkURL(_ data: Data) -> URL? {
        struct Response: Decodable {
            let results: [Result]
            struct Result: Decodable {
                let artworkUrl100: String?
                let artworkUrl512: String?
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let first = response.results.first else { return nil }
        let urlString = first.artworkUrl512 ?? first.artworkUrl100
        return urlString.flatMap(URL.init(string:))
    }

    /// Sample the icon to a tiny grid and read corner/center pixels for a diagonal
    /// gradient, plus average luminance to pick black-or-white text.
    private static func extractArt(from image: UIImage) -> (gradient: [Color], text: Color) {
        guard let cgImage = image.cgImage else { return ([], .white) }
        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return ([], .white) }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * w + x) * 4
            return (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
        }

        // CGContext origin is bottom-left, so y = h-1 is the visual top.
        let topLeading = rgb(0, h - 1)
        let center = rgb(w / 2, h / 2)
        let bottomTrailing = rgb(w - 1, 0)

        let samples = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w / 2, h / 2)]
        var r = 0.0, g = 0.0, b = 0.0
        for (x, y) in samples {
            let c = rgb(x, y); r += c.0; g += c.1; b += c.2
        }
        let n = Double(samples.count)
        let luminance = 0.299 * (r / n) + 0.587 * (g / n) + 0.114 * (b / n)
        let text: Color = luminance > 0.62 ? .black : .white

        let gradient = [
            Color(red: topLeading.0, green: topLeading.1, blue: topLeading.2),
            Color(red: center.0, green: center.1, blue: center.2),
            Color(red: bottomTrailing.0, green: bottomTrailing.1, blue: bottomTrailing.2),
        ]
        return (gradient, text)
    }
}
