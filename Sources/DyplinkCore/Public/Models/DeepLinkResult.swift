import Foundation

/// A resolved Dyplink deep link — either from a direct Universal Link /
/// custom URL scheme intent or from deferred post-install matching.
public struct DeepLinkResult: Sendable, Equatable {
    public let url: String
    public let shortCode: String?
    public let params: [String: AnyJSONValue]?
    public let isDeferred: Bool
    public let linkId: String?

    public init(
        url: String,
        shortCode: String? = nil,
        params: [String: AnyJSONValue]? = nil,
        isDeferred: Bool,
        linkId: String? = nil
    ) {
        self.url = url
        self.shortCode = shortCode
        self.params = params
        self.isDeferred = isDeferred
        self.linkId = linkId
    }
}

/// Result of a `Dyplink.shared.matchDeferredDeepLink` call.
public struct DeferredMatchResult: Sendable, Equatable {
    public let matched: Bool
    public let linkId: String?
    public let shortCode: String?
    public let params: [String: AnyJSONValue]?

    public init(
        matched: Bool,
        linkId: String? = nil,
        shortCode: String? = nil,
        params: [String: AnyJSONValue]? = nil
    ) {
        self.matched = matched
        self.linkId = linkId
        self.shortCode = shortCode
        self.params = params
    }

    public static let unmatched = DeferredMatchResult(matched: false)
}

/// Protocol-based listener for deep link events. Alternative to the
/// `Dyplink.shared.onDeepLink` closure — use whichever suits your
/// code style.
public protocol DeepLinkListener: AnyObject {
    func dyplink(_ dyplink: Dyplink, didReceive result: DeepLinkResult)
}
