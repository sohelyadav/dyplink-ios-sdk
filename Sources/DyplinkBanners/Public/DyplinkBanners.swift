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

        if let cached = cachedCategory(categoryId) {
            return cached
        }

        let category = try await apiClient.fetchBanners(categoryId: categoryId)
        store(category, as: categoryId)
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

    // ── Cache ──────────────────────────────────────────────────────────

    /// Both halves of the cache are reached through synchronous methods
    /// rather than locking inside `loadBanners`: `NSLock.lock()` is
    /// unavailable from an async context, because a lock held across an
    /// `await` can deadlock when the continuation resumes on the thread
    /// holding it. Nothing here is held across the fetch — that is exactly
    /// why it can be split in two.
    private func cachedCategory(_ categoryId: String) -> BannerCategory? {
        lock.lock(); defer { lock.unlock() }
        return cache[categoryId]
    }

    private func store(_ category: BannerCategory, as categoryId: String) {
        lock.lock(); defer { lock.unlock() }
        cache[categoryId] = category
    }
}
