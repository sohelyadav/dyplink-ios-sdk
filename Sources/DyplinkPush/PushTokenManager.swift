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

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DyplinkError.networkError(message: "Non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw DyplinkError.apiError(
                message: "Push token registration failed",
                statusCode: http.statusCode
            )
        }

        lock.lock()
        currentToken = token
        lock.unlock()
    }

    /// Unregister the current token from the backend.
    func unregisterToken() async throws {
        let baseUrl = DyplinkConfigBridge.baseUrl
        let apiKey = DyplinkConfigBridge.apiKey
        let projectId = DyplinkConfigBridge.projectId

        lock.lock()
        let token = currentToken
        lock.unlock()

        guard let token = token else { return }

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
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // Log but don't rethrow — best effort
            }
        } catch {
            // Swallow — local state is cleared regardless
        }

        lock.lock()
        currentToken = nil
        lock.unlock()
    }
}
