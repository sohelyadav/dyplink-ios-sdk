import Foundation
import DyplinkCore

/// Manages APNs push token registration and unregistration with the
/// Dyplink backend. Mirrors Android's `PushTokenManager` but uses
/// APNs device tokens instead of FCM tokens.
internal final class PushTokenManager {

    private var currentToken: String?
    private let lock = NSLock()

    var isRegistered: Bool {
        lock.lock(); defer { lock.unlock() }
        return currentToken != nil
    }

    /// Register the given APNs token string with the Dyplink backend.
    func registerToken(_ token: String) async throws {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey
        let projectId = DyplinkConfigBridge.projectId
        let fingerprint = DyplinkConfigBridge.deviceFingerprint

        let body: [String: Any] = [
            "projectId": projectId,
            "deviceFingerprint": fingerprint,
            "token": token,
            "platform": "ios",
            "provider": "apns",
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: "\(baseUrl)/api/push-tokens/register") else {
            throw DyplinkError.invalidConfig("Invalid push register URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DyplinkError.networkError(message: "Non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            // The body says *why* the registration was refused — a project
            // mismatch reads nothing like a malformed token — so it travels
            // with the error rather than being dropped on the floor.
            DyplinkDiagnostics.httpFailure(
                "POST /api/push-tokens/register",
                statusCode: http.statusCode,
                body: data
            )
            throw DyplinkError.apiError(
                message: "Push token registration failed",
                statusCode: http.statusCode,
                responseBody: String(data: data, encoding: .utf8)
            )
        }

        setCurrentToken(token)
    }

    /// Unregister the current token from the backend.
    func unregisterToken() async throws {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey
        let projectId = DyplinkConfigBridge.projectId

        guard let token = currentTokenValue() else { return }

        var components = URLComponents(string: "\(baseUrl)/api/push-tokens/unregister")
        components?.queryItems = [
            URLQueryItem(name: "projectId", value: projectId),
            URLQueryItem(name: "token", value: token),
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // Best effort, but not silent: a token the backend still
                // believes in goes on receiving campaigns after a logout.
                DyplinkDiagnostics.httpFailure(
                    "DELETE /api/push-tokens/unregister",
                    statusCode: http.statusCode,
                    body: data
                )
            }
        } catch {
            // Swallow — local state is cleared regardless.
            DyplinkDiagnostics.transportFailure("DELETE /api/push-tokens/unregister", error)
        }

        setCurrentToken(nil)
    }

    // ── Token state ────────────────────────────────────────────────────

    /// Reading and writing the token happen in synchronous methods of their
    /// own because `NSLock.lock()` is unavailable from an async context: a
    /// lock held across an `await` can deadlock when the continuation
    /// resumes on the thread holding it. Neither of these holds it across
    /// the request, which is what makes the split possible at all.
    private func currentTokenValue() -> String? {
        lock.lock(); defer { lock.unlock() }
        return currentToken
    }

    private func setCurrentToken(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        currentToken = token
    }
}
