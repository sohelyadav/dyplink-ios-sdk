import Foundation

/// Typed errors surfaced by the Dyplink SDK.
///
/// Mirrors the `DyplinkError` sealed class hierarchy on Android. Every
/// case carries a `localizedDescription` so it can be logged without
/// manual unwrapping.
public enum DyplinkError: Error, CustomStringConvertible, Sendable {

    /// The SDK has not been initialized via `Dyplink.shared.initialize`.
    case notInitialized(String = "Dyplink SDK not initialized")

    /// The SDK was configured with invalid parameters.
    case invalidConfig(String)

    /// A transport-level network failure — no response received, or a
    /// response whose status we could not interpret.
    case networkError(message: String, statusCode: Int? = nil, underlying: Error? = nil)

    /// The server returned a non-success HTTP status.
    case apiError(message: String, statusCode: Int, responseBody: String? = nil)

    public var description: String {
        switch self {
        case .notInitialized(let msg):
            return "DyplinkError.notInitialized: \(msg)"
        case .invalidConfig(let msg):
            return "DyplinkError.invalidConfig: \(msg)"
        case .networkError(let msg, let code, _):
            return "DyplinkError.networkError: \(msg)\(code.map { " (status \($0))" } ?? "")"
        case .apiError(let msg, let code, _):
            return "DyplinkError.apiError: \(msg) (status \(code))"
        }
    }
}

extension DyplinkError: LocalizedError {
    public var errorDescription: String? { description }
}
