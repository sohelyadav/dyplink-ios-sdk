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
    func report(campaignId: String, type: String, actionId: String? = nil) async {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey
        let projectId = DyplinkConfigBridge.projectId
        let fingerprint = DyplinkConfigBridge.deviceFingerprint

        var body: [String: Any] = [
            "projectId": projectId,
            "campaignId": campaignId,
            "deviceFingerprint": fingerprint,
            "type": type,
            "platform": "ios",
            "occurredAt": Self.iso8601Now(),
        ]
        // Which button, when it was a button. The same shape Android's
        // `PushEventReporter` sends, because one campaign's numbers are read
        // in one report: the server stores this on the event, and a report
        // that separates the two platforms' field names separates nothing.
        if let actionId = actionId {
            body["metadata"] = ["actionId": actionId]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(baseUrl)/api/push-notifications/events")
        else {
            DyplinkDiagnostics.warn(
                "Push \(type) for campaign \(campaignId) not reported: \(baseUrl) is not a usable base URL"
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        // Still fire-and-forget — a lost report must not disturb the
        // notification it belongs to — but no longer silent. `_ = try? await`
        // was how a campaign whose every event the server rejected read as a
        // campaign nobody had engaged with.
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DyplinkDiagnostics.httpFailure(
                    "POST /api/push-notifications/events (\(type))",
                    statusCode: http.statusCode,
                    body: data
                )
            }
        } catch {
            DyplinkDiagnostics.transportFailure(
                "POST /api/push-notifications/events (\(type))",
                error
            )
        }
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
