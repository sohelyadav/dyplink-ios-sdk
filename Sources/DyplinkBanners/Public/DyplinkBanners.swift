import Foundation
import DyplinkCore

/// Entry point for Dyplink in-app banners.
///
/// Two ways to use banners:
/// 1. Drop a `BannerCarouselView` into your view hierarchy (UIKit).
/// 2. Call `loadBanners(categoryId:)` to get the data and render
///    your own UI.
///
/// Requires `Dyplink.shared.initialize` first.
public final class DyplinkBanners: @unchecked Sendable {
    public static let shared = DyplinkBanners()

    private let apiClient = BannerApiClient()
    private var cache: [String: BannerCategory] = [:]
    private let lock = NSLock()

    private init() {}

    /// Fetch banners for the given category. Results are cached in
    /// memory; subsequent calls within the same session return the
    /// cached data instantly.
    public func loadBanners(categoryId: String) async throws -> BannerCategory {
        precondition(Dyplink.shared.isInitialized,
                     "Dyplink.shared.initialize(config:) must be called first")

        lock.lock()
        if let cached = cache[categoryId] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let category = try await apiClient.fetchBanners(categoryId: categoryId)

        lock.lock()
        cache[categoryId] = category
        lock.unlock()

        return category
    }

    /// Clear the in-memory banner cache.
    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
        #if canImport(UIKit)
        BannerImageLoader.shared.clearCache()
        #endif
    }
}
