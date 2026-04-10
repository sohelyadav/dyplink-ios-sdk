import Foundation
import DyplinkCore

/// Fetches banner categories from `GET /api/in-app-banners/serve/:id`
/// and tracks banner clicks via `POST /api/in-app-banners/:id/click`.
///
/// Mirrors the Android `BannerApiClient`.
internal final class BannerApiClient {

    func fetchBanners(categoryId: String) async throws -> BannerCategory {
        let baseUrl = DyplinkConfigBridge.baseUrl
        guard let url = URL(string: "\(baseUrl)/api/in-app-banners/serve/\(categoryId)") else {
            throw DyplinkError.invalidConfig("Invalid banner URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DyplinkError.apiError(
                message: "Failed to fetch banners",
                statusCode: code
            )
        }

        return try Self.parse(data: data, categoryId: categoryId)
    }

    func trackClick(bannerId: String) async {
        let baseUrl = DyplinkConfigBridge.baseUrl
        guard let url = URL(string: "\(baseUrl)/api/in-app-banners/\(bannerId)/click") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.timeoutInterval = 15

        _ = try? await URLSession.shared.data(for: request)
    }

    // ── JSON parsing ───────────────────────────────────────────────────

    private static func parse(data: Data, categoryId: String) throws -> BannerCategory {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DyplinkError.apiError(message: "Invalid banner JSON", statusCode: 0)
        }

        let wrapped = (root["data"] as? [String: Any]) ?? root
        let categoryJson = (wrapped["category"] as? [String: Any]) ?? wrapped
        let bannersArray = (wrapped["banners"] as? [[String: Any]])
            ?? (categoryJson["banners"] as? [[String: Any]])
            ?? []

        let banners = bannersArray.compactMap { b -> DyplinkBanner? in
            let isActive = b["isActive"] as? Bool ?? true
            guard isActive else { return nil }
            return DyplinkBanner(
                id: b["id"] as? String ?? "",
                title: b["title"] as? String ?? "",
                imageUrl: b["imageUrl"] as? String,
                clickUrl: b["clickUrl"] as? String,
                ctaText: b["ctaText"] as? String,
                sortOrder: b["sortOrder"] as? Int ?? 0,
                isActive: true,
                metadata: Self.parseMetadata(b["metadata"] as? [String: Any])
            )
        }.sorted { $0.sortOrder < $1.sortOrder }

        return BannerCategory(
            id: categoryJson["id"] as? String ?? categoryId,
            name: categoryJson["name"] as? String ?? "",
            layout: categoryJson["layout"] as? String ?? "carousel",
            aspectRatio: categoryJson["aspectRatio"] as? String,
            autoRotate: categoryJson["autoRotate"] as? Bool ?? true,
            rotationInterval: categoryJson["rotationInterval"] as? Int ?? 5,
            heading: categoryJson["heading"] as? String,
            backgroundColor: categoryJson["backgroundColor"] as? String ?? "#ffffff",
            padding: categoryJson["padding"] as? Int ?? 0,
            banners: banners
        )
    }

    private static func parseMetadata(_ json: [String: Any]?) -> [String: AnyJSONValue]? {
        guard let json = json, !json.isEmpty else { return nil }
        return json.mapValues { AnyJSONValue($0) }
    }
}
