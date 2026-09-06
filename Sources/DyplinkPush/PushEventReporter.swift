import Foundation
import DyplinkCore

/// Reports push notification engagement (delivered/impression/click/
/// dismissed) to the Dyplink backend. Mirrors `PushTokenManager`'s
/// networking style, but fire-and-forget like `MessageApiClient
/// .recordEvent` and `BannerApiClient.trackClick` — a failed report is
/// swallowed, never surfaced to the caller, since it must never disrupt
/// notification handling.
internal final class PushEventReporter {

    /// POST a single engagement event to `/api/push-notifications/events`.
    /// Never throws.
    func report(campaignId: String, type: String) async {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey
        let projectId = DyplinkConfigBridge.projectId
        let fingerprint = DyplinkConfigBridge.deviceFingerprint

        let body: [String: Any] = [
            "projectId": projectId,
            "campaignId": campaignId,
            "deviceFingerprint": fingerprint,
            "type": type,
            "platform": "ios",
            "occurredAt": Self.iso8601Now(),
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(baseUrl)/api/push-notifications/events")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        _ = try? await URLSession.shared.data(for: request)
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
