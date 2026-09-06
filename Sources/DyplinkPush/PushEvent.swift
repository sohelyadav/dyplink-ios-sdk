import Foundation

/// The kind of push engagement event reported to the Dyplink backend.
///
/// Mirrors the `type` values accepted by
/// `POST /api/push-notifications/events`.
public enum PushEvent: String, Sendable {
    case delivered
    case impression
    case click
    case dismissed
}
