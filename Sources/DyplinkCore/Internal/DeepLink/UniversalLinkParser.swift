import Foundation

/// Parses incoming `URL`s to extract Dyplink deep link data.
///
/// Matches the Android `IntentParser` logic:
///   * URL host must be in `deepLinkHosts`, OR
///   * URL scheme must equal `customScheme`
/// The first path segment matching `^[A-Za-z0-9_-]{5,10}$` is treated
/// as the short code; query parameters become the `params` map.
internal final class UniversalLinkParser {

    private let deepLinkHosts: [String]
    private let customScheme: String?

    init(deepLinkHosts: [String], customScheme: String?) {
        self.deepLinkHosts = deepLinkHosts.map { $0.lowercased() }
        self.customScheme = customScheme?.lowercased()
    }

    /// Returns a `DeepLinkResult` if the URL is a recognized Dyplink
    /// link, or `nil` otherwise.
    func parse(_ url: URL) -> DeepLinkResult? {
        guard isRecognized(url) else {
            DyplinkLogger.d("UniversalLinkParser: URL not recognized — \(url)")
            return nil
        }

        let shortCode = extractShortCode(url)
        let params = extractQueryParams(url)

        return DeepLinkResult(
            url: url.absoluteString,
            shortCode: shortCode,
            params: params.isEmpty ? nil : params.mapValues { AnyJSONValue($0) },
            isDeferred: false,
            linkId: nil
        )
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private func isRecognized(_ url: URL) -> Bool {
        if let host = url.host?.lowercased(), deepLinkHosts.contains(host) {
            return true
        }
        if let scheme = url.scheme?.lowercased(),
           let custom = customScheme, scheme == custom {
            return true
        }
        return false
    }

    private func extractShortCode(_ url: URL) -> String? {
        let segments = url.pathComponents.filter { $0 != "/" }
        return segments.first { Self.shortCodeRegex.firstMatch(
            in: $0,
            options: [],
            range: NSRange(location: 0, length: $0.utf16.count)
        ) != nil }
    }

    private func extractQueryParams(_ url: URL) -> [String: Any] {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else { return [:] }

        var grouped: [String: [String]] = [:]
        for item in items {
            grouped[item.name, default: []].append(item.value ?? "")
        }

        var out: [String: Any] = [:]
        for (key, values) in grouped {
            if values.count == 1 {
                out[key] = values[0]
            } else {
                out[key] = values.joined(separator: ",")
            }
        }
        return out
    }

    private static let shortCodeRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]{5,10}$")
    }()
}
