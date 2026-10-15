import Foundation
import DyplinkCore

/// Calls `POST /api/messages/check` and `POST /api/messages/event`.
/// Mirrors the Android `MessageApiClient`.
internal final class MessageApiClient {

    struct CheckContext {
        var screen: String?
        var event: String?
        var appVersion: String?
        var sessionDuration: Int?
        var country: String?
        var language: String?
    }

    func checkMessages(
        projectId: String,
        deviceFingerprint: String,
        distinctId: String?,
        context: CheckContext
    ) async throws -> [InAppMessage] {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey

        var contextDict: [String: Any] = ["platform": "ios"]
        if let v = context.screen { contextDict["screen"] = v }
        if let v = context.event { contextDict["event"] = v }
        if let v = context.appVersion { contextDict["appVersion"] = v }
        if let v = context.sessionDuration { contextDict["sessionDuration"] = v }
        if let v = context.country { contextDict["country"] = v }
        if let v = context.language { contextDict["language"] = v }

        var body: [String: Any] = [
            "projectId": projectId,
            "deviceFingerprint": deviceFingerprint,
            "context": contextDict,
        ]
        if let d = distinctId { body["distinctId"] = d }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: "\(baseUrl)/api/messages/check") else {
            throw DyplinkError.invalidConfig("Invalid messages URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // `checkAndShow` catches this and shows nothing, which is also
            // what "nobody is eligible" looks like — so the body the server
            // sent is the only thing that tells the two apart.
            DyplinkDiagnostics.httpFailure("POST /api/messages/check", statusCode: code, body: data)
            throw DyplinkError.apiError(
                message: "checkMessages failed",
                statusCode: code,
                responseBody: String(data: data, encoding: .utf8)
            )
        }

        return Self.parseMessages(from: data)
    }

    func recordEvent(
        messageId: String,
        projectId: String,
        deviceFingerprint: String,
        distinctId: String?,
        eventType: String,
        buttonId: String? = nil
    ) async {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey

        var body: [String: Any] = [
            "messageId": messageId,
            "projectId": projectId,
            "deviceFingerprint": deviceFingerprint,
            "eventType": eventType,
        ]
        if let d = distinctId { body["distinctId"] = d }
        if let b = buttonId { body["buttonId"] = b }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(baseUrl)/api/messages/event")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        // Fire-and-forget: a lost impression must not cost the user the
        // message. Reported, though — a campaign whose every event is
        // refused reads in the dashboard as a campaign nobody saw.
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DyplinkDiagnostics.httpFailure(
                    "POST /api/messages/event (\(eventType))",
                    statusCode: http.statusCode,
                    body: data
                )
            }
        } catch {
            DyplinkDiagnostics.transportFailure("POST /api/messages/event (\(eventType))", error)
        }
    }

    // ── Parsing ────────────────────────────────────────────────────────

    /// Reads the eligible messages out of a `/api/messages/check` body.
    ///
    /// The API wraps every response in `{ "data": … }`. Reading `messages`
    /// off the root finds nothing and looks exactly like "no messages are
    /// eligible" — so for as long as this read the root directly, nothing
    /// ever displayed and nothing ever complained. Falling back to the root
    /// keeps an unwrapped body working.
    ///
    /// Anything unreadable yields no messages rather than an error: there is
    /// nothing the host app could do about a malformed check.
    internal static func parseMessages(from data: Data) -> [InAppMessage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let json = (root["data"] as? [String: Any]) ?? root
        guard let messagesArray = json["messages"] as? [[String: Any]] else { return [] }
        return messagesArray.map(parseMessage)
    }

    private static func parseMessage(_ json: [String: Any]) -> InAppMessage {
        InAppMessage(
            id: json["id"] as? String ?? "",
            messageType: json["messageType"] as? String ?? "modal",
            title: json["title"] as? String ?? "",
            body: (json["body"] as? String).nonEmpty,
            imageUrl: (json["imageUrl"] as? String).nonEmpty,
            imagePosition: json["imagePosition"] as? String ?? "top",
            buttons: parseButtons(json["buttons"] as? [[String: Any]]),
            theme: parseTheme(json["theme"] as? [String: Any]),
            dismissOnTapOutside: json["dismissOnTapOutside"] as? Bool ?? true,
            // Zero is "no auto-dismiss" in the dashboard, and `@Min(0)` lets
            // it through — but as an *explicit* zero it also suppressed the
            // banner default, so a banner with no buttons arrived with
            // nothing to close it. Absent and zero mean the same thing here:
            // let the layout decide, which gives a banner its 4 seconds and
            // leaves a modal open until the user closes it.
            autoDismissSeconds: (json["autoDismissSeconds"] as? Int).flatMap { $0 > 0 ? $0 : nil },
            triggerDelay: json["triggerDelay"] as? Int ?? 0
        )
    }

    private static func parseButtons(_ array: [[String: Any]]?) -> [MessageButton]? {
        guard let array = array, !array.isEmpty else { return nil }
        return array.map { b in
            MessageButton(
                id: b["id"] as? String ?? "",
                text: b["text"] as? String ?? "",
                action: b["action"] as? String ?? "dismiss",
                actionUrl: (b["actionUrl"] as? String).nonEmpty,
                actionEvent: (b["actionEvent"] as? String).nonEmpty,
                style: b["style"] as? String ?? "primary"
            )
        }
    }

    private static func parseTheme(_ json: [String: Any]?) -> MessageTheme? {
        guard let json = json else { return nil }
        return MessageTheme(
            backgroundColor: (json["backgroundColor"] as? String).nonEmpty,
            textColor: (json["textColor"] as? String).nonEmpty,
            titleColor: (json["titleColor"] as? String).nonEmpty,
            buttonPrimaryColor: (json["buttonPrimaryColor"] as? String).nonEmpty,
            buttonSecondaryColor: (json["buttonSecondaryColor"] as? String).nonEmpty,
            overlayColor: (json["overlayColor"] as? String).nonEmpty,
            borderRadius: (json["borderRadius"] as? Int).flatMap { $0 >= 0 ? $0 : nil },
            animation: (json["animation"] as? String).nonEmpty
        )
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}
