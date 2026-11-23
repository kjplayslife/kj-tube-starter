import ImageIO
import SwiftUI
import UIKit

/// Thumbnails and avatars from one shared disk cache, so an image shown once never flashes in
/// again, even after a relaunch or offline (speed-and-polish ⚙︎). Replaces `AsyncImage`, which
/// doesn't cache reliably.
///
/// Smooth scrolling: reading from disk and decoding happen off the main thread, already shrunk
/// to card size, so a card scrolling into view only ever does a memory lookup. The few cards
/// shown at launch are warmed once, before the first frame, so they still never pop in.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    /// Widest an image is kept, in pixels: a full-width card on the biggest iPhone at 3×.
    /// A 1280 × 720 maxres thumbnail shrinks to about 1150 × 650.
    nonisolated static let maxPixels = 1150

    // URLCache and URLSession are thread-safe; Swift just can't always tell.
    nonisolated(unsafe) private static let disk = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    nonisolated(unsafe) static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = disk
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
    private let memory = NSCache<NSURL, UIImage>()
    /// Loads already running, so a prefetch and a card asking at once share one download and decode.
    private var loading: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        memory.totalCostLimit = 150 * 1024 * 1024
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Reads these images from disk right now, on the main thread. Only for the handful of cards
    /// visible in the very first frame after a cold start; everything else loads off the main thread.
    func warmFromDisk(_ sources: [[URL]]) {
        for urls in sources {
            guard let key = urls.first, cached(key) == nil,
                  let image = Self.fromDisk(urls) else { continue }
            store(image, key)
        }
    }

    func image(for url: URL) async -> UIImage? {
        await image(from: [url])
    }

    /// The first of `urls` that loads, cached under the first one: disk first, then the network.
    /// YouTube answers a missing thumbnail size with a 404 and a grey placeholder, so only a 200 counts.
    func image(from urls: [URL]) async -> UIImage? {
        guard let key = urls.first else { return nil }
        if let hit = cached(key) { return hit }
        if let running = loading[key] { return await running.value }
        let task = Task { await Self.load(urls) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { store(image, key) }
        return image
    }

    /// Warms the cache for images about to be shown (e.g. a new shipment's thumbnails).
    /// Each entry is a list of fallbacks, as for `image(from:)`.
    func prefetch(_ sources: [[URL]]) {
        for urls in sources where urls.first.map({ cached($0) == nil }) ?? false {
            Task { _ = await image(from: urls) }
        }
    }

    private func store(_ image: UIImage, _ key: URL) {
        memory.setObject(image, forKey: key as NSURL, cost: Self.bytes(image))
    }

    /// Decoded size, so the memory limit counts what images really take.
    private static func bytes(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// Runs off the main thread (a nonisolated async function).
    private nonisolated static func load(_ urls: [URL]) async -> UIImage? {
        if let image = fromDisk(urls) { return image }
        for url in urls {
            guard let (data, response) = try? await session.data(from: url),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) == 200,
                  let image = decode(data) else { continue }
            return image
        }
        return nil
    }

    /// The first of `urls` saved on disk by an earlier load, decoded.
    private nonisolated static func fromDisk(_ urls: [URL]) -> UIImage? {
        for url in urls {
            guard let response = disk.cachedResponse(for: URLRequest(url: url)),
                  ((response.response as? HTTPURLResponse)?.statusCode ?? 200) == 200,
                  let image = decode(response.data) else { continue }
            return image
        }
        return nil
    }

    /// Decodes now (not lazily at first draw, which would land on the main thread mid-scroll),
    /// shrunk to at most `maxPixels` wide or tall. Smaller images keep their size.
    nonisolated static func decode(_ data: Data, maxPixels limit: Int = ImageCache.maxPixels) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct CachedImage: View {
    /// Tried in order; the first that loads is shown.
    let urls: [URL]
    @State private var image: UIImage?

    init(url: URL?) {
        self.init(urls: url.map { [$0] } ?? [])
    }

    init(urls: [URL]) {
        self.urls = urls
        // Memory only: never touch the disk on the main thread while scrolling.
        _image = State(initialValue: urls.first.flatMap(ImageCache.shared.cached))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: urls) {
            // The same view can be handed new URLs (the player's avatar when the video changes),
            // so never keep showing the previous image.
            image = urls.first.flatMap(ImageCache.shared.cached)
            guard image == nil, !urls.isEmpty else { return }
            image = await ImageCache.shared.image(from: urls)
        }
    }
}

/// A video's thumbnail, sharpest first (D73): maxres is 1280 × 720 but missing on some videos,
/// sd is 640 × 480, hq (480 × 360) always exists.
enum Thumbnail {
    static func urls(_ videoID: String) -> [URL] {
        ["maxresdefault", "sddefault", "hqdefault"].map {
            URL(string: "https://i.ytimg.com/vi/\(videoID)/\($0).jpg")!
        }
    }
}
