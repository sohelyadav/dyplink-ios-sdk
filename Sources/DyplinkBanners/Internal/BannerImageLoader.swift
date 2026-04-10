import Foundation
#if canImport(UIKit)
import UIKit

/// Simple image loader backed by `URLSession` + `NSCache`.
/// Replaces Glide/Coil/Kingfisher for this SDK — zero external deps.
internal final class BannerImageLoader {
    static let shared = BannerImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session = URLSession(configuration: .ephemeral)

    func load(url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.cache.setObject(image, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
#endif
