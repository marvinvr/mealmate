import ImageIO
import SwiftUI
import UIKit
import CryptoKit

/// A recipe photo that fills whatever frame it gets (clipped, `.fill`), with
/// `RecipeImagePlaceholder` while loading, on failure or when the recipe has no image.
///
/// Size choice (STYLE.md §5): hero → `.original`, cards → `.min`, thumbnails (≤ 64pt) → `.tiny`.
/// Give it a frame or aspect ratio at the call site and clip it with `.recipeImageShape()`:
///
/// ```swift
/// RecipeImage(recipe: summary)                       // card (min-original)
///     .aspectRatio(Theme.Aspect.card, contentMode: .fit)
///     .recipeImageShape()
/// RecipeImage(recipe: summary, size: .tiny)          // list thumbnail
///     .frame(width: 56, height: 56)
///     .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
/// ```
///
/// Images go through `RecipeImageLoader` (memory + disk cache keyed by URL; the URL carries
/// the image key, so a changed photo gets a new URL). A cached image shows on the first
/// frame without a fade; freshly loaded ones fade in. While a large `.original` loads, an
/// already cached `.min` of the same recipe is shown in its place.
struct RecipeImage: View {
    let recipeID: String
    let imageKey: String?
    var size: RecipeImageSize = .min
    /// Placeholder tone seed (defaults to the recipe ID).
    var seed: String?

    @Environment(\.mealie) private var mealie
    @State private var loaded: LoadedImage?

    init(recipeID: String, imageKey: String?, size: RecipeImageSize = .min, seed: String? = nil) {
        self.recipeID = recipeID
        self.imageKey = imageKey
        self.size = size
        self.seed = seed
    }

    init(recipe: RecipeSummary, size: RecipeImageSize = .min) {
        self.init(recipeID: recipe.id, imageKey: recipe.hasImage ? recipe.imageKey : nil, size: size)
    }

    init(recipe: Recipe, size: RecipeImageSize = .original) {
        self.init(recipeID: recipe.id, imageKey: recipe.hasImage ? recipe.imageKey : nil, size: size)
    }

    private struct LoadedImage: Equatable {
        let url: URL
        let image: UIImage
    }

    var body: some View {
        let url = imageURL(size)
        let image = currentImage(for: url)
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    RecipeImagePlaceholder(seed: seed ?? recipeID)
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url, loaded?.url != url else { return }
                if RecipeImageLoader.memoryImage(for: url) != nil { return }
                guard let fetched = await RecipeImageLoader.shared.image(for: url, size: size) else { return }
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.3)) {
                    loaded = LoadedImage(url: url, image: fetched)
                }
            }
    }

    private func imageURL(_ size: RecipeImageSize) -> URL? {
        guard let imageKey, !imageKey.isEmpty else { return nil }
        return mealie.recipeImageURL(recipeID: recipeID, imageKey: imageKey, size: size)
    }

    private func currentImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        if let cached = RecipeImageLoader.memoryImage(for: url) { return cached }
        // Progressive hero: show the card-sized variant while the original loads.
        if size == .original, let smaller = imageURL(.min) {
            return RecipeImageLoader.memoryImage(for: smaller)
        }
        return nil
    }
}

// MARK: - Loader & cache

/// Memory + disk cache for recipe photos and user avatars (`UserAvatar`).
///
/// Mealie's media responses send `Cache-Control: no-cache`, so `URLCache` would revalidate
/// every image on every appearance. Recipe image URLs already change when the photo changes
/// (`?version=<imageKey>`), so this cache treats a URL as immutable: memory (`NSCache`) →
/// disk (`Caches/RecipeImages`) → network, with in-flight requests de-duplicated. A disk hit
/// older than `revalidationInterval` is shown immediately and refreshed in the background.
/// Images are decoded and downsampled off the main thread (ImageIO), so scrolling a grid
/// never decodes WebP on the main thread. A 404 is remembered (in memory) so a missing avatar
/// isn't requested on every appearance.
///
/// Avatar URLs are the exception to "immutable": Mealie keeps a user's `cacheKey` when the file
/// changes without an upload or OIDC sync (and every user starts on the same default key), so
/// `refresh(_:maxPixelSize:)` re-downloads them like a browser revalidates, throttled per URL.
actor RecipeImageLoader {
    static let shared = RecipeImageLoader()

    /// Re-download a disk-cached image at most this often (it's shown from disk meanwhile).
    static let revalidationInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Disk budget; the oldest files are removed once per launch when it's exceeded.
    static let diskLimit = 300 * 1024 * 1024

    private nonisolated static let memory: MemoryCache = MemoryCache()

    private let directory: URL
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var revalidating: Set<URL> = []
    /// URLs the server answered with 404 (no avatar / photo). Cleared by `removeAll()`.
    private var missing: Set<URL> = []
    /// Last network fetch per URL, for `refresh`'s throttle.
    private var fetchedAt: [URL: Date] = [:]
    private var didTrim = false

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = caches.appending(path: "RecipeImages", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    /// Synchronous memory lookup for the first frame (thread-safe).
    nonisolated static func memoryImage(for url: URL) -> UIImage? {
        memory.image(for: url)
    }

    /// Cached or downloaded recipe photo; `nil` when it can't be loaded (placeholder stays).
    func image(for url: URL, size: RecipeImageSize) async -> UIImage? {
        await image(for: URLRequest(url: url), maxPixelSize: Self.maxPixelSize(for: size))
    }

    /// Cached or downloaded image for `request` (cache key: its URL, so the URL must change
    /// when the image does). `nil` when it can't be loaded or the server has none (404).
    func image(for request: URLRequest, maxPixelSize maxPixel: CGFloat) async -> UIImage? {
        guard let url = request.url else { return nil }
        if let image = Self.memory.image(for: url) { return image }
        if missing.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }

        trimDiskIfNeeded()
        let file = fileURL(for: url)
        let task = Task.detached(priority: .userInitiated) { [session] () -> UIImage? in
            if let data = try? Data(contentsOf: file), let image = Self.decode(data, maxPixelSize: maxPixel) {
                let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    .map { Date().timeIntervalSince($0) } ?? 0
                if age > Self.revalidationInterval {
                    await self.revalidate(request, file: file, maxPixel: maxPixel)
                }
                return image
            }
            switch await Self.download(request, session: session) {
            case .data(let data):
                await self.noteFetched(url)
                guard let image = Self.decode(data, maxPixelSize: maxPixel) else { return nil }
                try? data.write(to: file, options: .atomic)
                return image
            case .missing:
                await self.noteFetched(url)
                await self.markMissing(url)
                return nil
            case .failed:
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { Self.memory.store(image, for: url) }
        return image
    }

    enum Refresh {
        /// The server's current image (now also in memory and on disk).
        case image(UIImage)
        /// The server has none (404); the cached copy was dropped.
        case missing
        /// Fetched within `minInterval`, or the request failed: keep what is shown.
        case unchanged
    }

    /// Re-downloads `request`, bypassing memory, disk and the 404 memo, and updates the caches.
    /// For images whose URL doesn't change with the content (user avatars). At most once per
    /// `minInterval` per URL, counting the initial download.
    func refresh(_ request: URLRequest, maxPixelSize maxPixel: CGFloat, minInterval: TimeInterval) async -> Refresh {
        guard let url = request.url else { return .unchanged }
        if let last = fetchedAt[url], Date().timeIntervalSince(last) < minInterval { return .unchanged }
        if let task = inFlight[url] { _ = await task.value; return .unchanged }
        fetchedAt[url] = Date()
        let file = fileURL(for: url)
        switch await Self.download(request, session: session) {
        case .data(let data):
            guard let image = Self.decode(data, maxPixelSize: maxPixel) else { return .unchanged }
            try? data.write(to: file, options: .atomic)
            Self.memory.store(image, for: url)
            missing.remove(url)
            return .image(image)
        case .missing:
            Self.memory.remove(url)
            try? FileManager.default.removeItem(at: file)
            missing.insert(url)
            return .missing
        case .failed:
            return .unchanged
        }
    }

    /// Removes all cached images (memory and disk).
    func removeAll() {
        Self.memory.removeAll()
        missing.removeAll()
        fetchedAt.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Private

    private func revalidate(_ request: URLRequest, file: URL, maxPixel: CGFloat) {
        guard let url = request.url, !revalidating.contains(url) else { return }
        revalidating.insert(url)
        let session = self.session
        Task.detached(priority: .background) {
            if case .data(let data) = await Self.download(request, session: session),
               let image = Self.decode(data, maxPixelSize: maxPixel) {
                try? data.write(to: file, options: .atomic)
                Self.memory.store(image, for: url)
            } else {
                // Keep the old file; try again after another interval.
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            }
            await self.finishRevalidation(url)
        }
    }

    private func finishRevalidation(_ url: URL) {
        revalidating.remove(url)
    }

    private func markMissing(_ url: URL) {
        missing.insert(url)
    }

    private func noteFetched(_ url: URL) {
        fetchedAt[url] = Date()
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name + ".img", directoryHint: .notDirectory)
    }

    private func trimDiskIfNeeded() {
        guard !didTrim else { return }
        didTrim = true
        let directory = self.directory
        Task.detached(priority: .background) {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
            var entries = files.compactMap { file -> (URL, Int, Date)? in
                guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
                return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
            }
            var total = entries.reduce(0) { $0 + $1.1 }
            guard total > Self.diskLimit else { return }
            entries.sort { $0.2 < $1.2 }
            for (file, size, _) in entries where total > Self.diskLimit * 3 / 4 {
                try? FileManager.default.removeItem(at: file)
                total -= size
            }
        }
    }

    private enum Download {
        case data(Data)
        /// 404: the server has no such image (e.g. a user without a profile picture).
        case missing
        /// Network error, other status or empty body; worth retrying later.
        case failed
    }

    private static func download(_ request: URLRequest, session: URLSession) async -> Download {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        if http.statusCode == 404 { return .missing }
        guard http.statusCode == 200, !data.isEmpty else { return .failed }
        return .data(data)
    }

    /// Longest edge in pixels. Generous enough for a 3x screen at the use site.
    private static func maxPixelSize(for size: RecipeImageSize) -> CGFloat {
        switch size {
        case .tiny: 300
        case .min: 900
        case .original: 2400
        }
    }

    /// Decodes (and downsamples) into a ready-to-draw bitmap.
    private static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// `NSCache` is thread-safe; it's only reached through the methods below.
    private final class MemoryCache: @unchecked Sendable {
        private let cache: NSCache<NSURL, UIImage> = {
            let cache = NSCache<NSURL, UIImage>()
            cache.totalCostLimit = 120 * 1024 * 1024
            return cache
        }()

        func image(for url: URL) -> UIImage? {
            cache.object(forKey: url as NSURL)
        }

        func store(_ image: UIImage, for url: URL) {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: url as NSURL, cost: cost)
        }

        func remove(_ url: URL) {
            cache.removeObject(forKey: url as NSURL)
        }

        func removeAll() {
            cache.removeAllObjects()
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        RecipeImage(recipeID: "preview-1", imageKey: nil)
            .aspectRatio(Theme.Aspect.card, contentMode: .fit)
            .recipeImageShape()
        RecipeImage(recipeID: "preview-2", imageKey: nil, size: .tiny)
            .frame(width: 56, height: 56)
            .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
    }
    .padding(Theme.Spacing.screen)
    .screenBackground()
}
