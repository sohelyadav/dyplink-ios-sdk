import Foundation

/// Parameters for `Dyplink.shared.trackConversion`.
///
/// Fields `shortCode` and `linkId` fall back to the attributed values
/// stored from a prior deferred-match result when not explicitly set.
public struct TrackConversionParams: Sendable {
    public let eventType: String
    public let shortCode: String?
    public let linkId: String?
    public let externalUserId: String?
    public let metadata: [String: AnyJSONValue]?

    public init(
        eventType: String,
        shortCode: String? = nil,
        linkId: String? = nil,
        externalUserId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.eventType = eventType
        self.shortCode = shortCode
        self.linkId = linkId
        self.externalUserId = externalUserId
        self.metadata = metadata?.mapValues { AnyJSONValue($0) }
    }
}
