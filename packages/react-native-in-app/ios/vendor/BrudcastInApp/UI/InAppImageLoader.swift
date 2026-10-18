#if canImport(UIKit)
import UIKit
import Brudcast

/// Downloads and caches message images with the platform's URL loading.
final class InAppImageLoader {
    static let shared = InAppImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1_024 * 1_024, diskCapacity: 50 * 1_024 * 1_024)
        session = URLSession(configuration: configuration)
        cache.countLimit = 64
    }

    /// The decoded image, when it has been loaded.
    ///
    /// - Parameter url: The image URL.
    /// - Returns: The image, or nil.
    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Loads every image before a message shows.
    ///
    /// - Parameters:
    ///   - urls: The design's image URLs.
    ///   - timeout: How long to wait for all of them.
    ///   - completion: Called once with true when every image loaded in time.
    func prefetch(_ urls: [URL], timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let missing = Array(Set(urls)).filter { image(for: $0) == nil }
        guard !missing.isEmpty else {
            completion(true)
            return
        }
        let lock = NSLock()
        var remaining = missing.count
        var failed = false
        var finished = false
        let finish: (Bool) -> Void = { ok in
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            completion(ok)
        }
        for url in missing {
            load(url, timeout: timeout) { image in
                lock.lock()
                remaining -= 1
                if image == nil {
                    failed = true
                }
                let done = remaining == 0
                let ok = !failed
                lock.unlock()
                if done || !ok {
                    finish(ok)
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            finish(false)
        }
    }

    /// Loads one image.
    ///
    /// - Parameters:
    ///   - url: The image URL.
    ///   - timeout: The request timeout.
    ///   - completion: Called with the image, or nil when it failed.
    func load(_ url: URL, timeout: TimeInterval = 15, completion: @escaping (UIImage?) -> Void) {
        if let cached = image(for: url) {
            completion(cached)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        session.dataTask(with: request) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let data = data, let image = UIImage(data: data) else {
                BrudcastLogger.shared.debug("Image failed to load: \(url.absoluteString)")
                completion(nil)
                return
            }
            let decoded = Self.decoded(image)
            self?.cache.setObject(decoded, forKey: url as NSURL)
            completion(decoded)
        }.resume()
    }

    private static func decoded(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
    }
}
#endif
