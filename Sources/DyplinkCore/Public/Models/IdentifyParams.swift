import Foundation

/// Parameters for `Dyplink.shared.identify`.
///
/// Build with `IdentifyParams.Builder()`:
/// ```swift
/// let params = IdentifyParams.Builder()
///     .externalUserId("user-123")
///     .firstName("Jane")
///     .traits(["plan": "pro", "age": 34])
///     .build()
/// ```
public struct IdentifyParams: Sendable {
    public let distinctId: String?
    public let externalUserId: String?
    public let firstName: String?
    public let lastName: String?
    public let phone: String?
    public let avatar: String?
    public let locale: String?
    public let language: String?
    public let appVersion: String?
    public let appBuild: String?
    public let traits: [String: AnyJSONValue]?
    public let utmSource: String?
    public let utmMedium: String?
    public let utmCampaign: String?
    public let utmContent: String?
    public let utmTerm: String?
    public let installSource: String?
    public let installCampaign: String?
    public let emailOptIn: Bool?
    public let smsOptIn: Bool?
    public let pushOptIn: Bool?
    public let gdprConsent: Bool?
    public let doNotTrack: Bool?

    public final class Builder {
        private var _distinctId: String?
        private var _externalUserId: String?
        private var _firstName: String?
        private var _lastName: String?
        private var _phone: String?
        private var _avatar: String?
        private var _locale: String?
        private var _language: String?
        private var _appVersion: String?
        private var _appBuild: String?
        private var _traits: [String: AnyJSONValue]?
        private var _utmSource: String?
        private var _utmMedium: String?
        private var _utmCampaign: String?
        private var _utmContent: String?
        private var _utmTerm: String?
        private var _installSource: String?
        private var _installCampaign: String?
        private var _emailOptIn: Bool?
        private var _smsOptIn: Bool?
        private var _pushOptIn: Bool?
        private var _gdprConsent: Bool?
        private var _doNotTrack: Bool?

        public init() {}

        @discardableResult public func distinctId(_ v: String) -> Builder { _distinctId = v; return self }
        @discardableResult public func externalUserId(_ v: String) -> Builder { _externalUserId = v; return self }
        @discardableResult public func firstName(_ v: String) -> Builder { _firstName = v; return self }
        @discardableResult public func lastName(_ v: String) -> Builder { _lastName = v; return self }
        @discardableResult public func phone(_ v: String) -> Builder { _phone = v; return self }
        @discardableResult public func avatar(_ v: String) -> Builder { _avatar = v; return self }
        @discardableResult public func locale(_ v: String) -> Builder { _locale = v; return self }
        @discardableResult public func language(_ v: String) -> Builder { _language = v; return self }
        @discardableResult public func appVersion(_ v: String) -> Builder { _appVersion = v; return self }
        @discardableResult public func appBuild(_ v: String) -> Builder { _appBuild = v; return self }
        @discardableResult public func traits(_ v: [String: Any]) -> Builder {
            _traits = v.mapValues { AnyJSONValue($0) }
            return self
        }
        @discardableResult public func utmSource(_ v: String) -> Builder { _utmSource = v; return self }
        @discardableResult public func utmMedium(_ v: String) -> Builder { _utmMedium = v; return self }
        @discardableResult public func utmCampaign(_ v: String) -> Builder { _utmCampaign = v; return self }
        @discardableResult public func utmContent(_ v: String) -> Builder { _utmContent = v; return self }
        @discardableResult public func utmTerm(_ v: String) -> Builder { _utmTerm = v; return self }
        @discardableResult public func installSource(_ v: String) -> Builder { _installSource = v; return self }
        @discardableResult public func installCampaign(_ v: String) -> Builder { _installCampaign = v; return self }
        @discardableResult public func emailOptIn(_ v: Bool) -> Builder { _emailOptIn = v; return self }
        @discardableResult public func smsOptIn(_ v: Bool) -> Builder { _smsOptIn = v; return self }
        @discardableResult public func pushOptIn(_ v: Bool) -> Builder { _pushOptIn = v; return self }
        @discardableResult public func gdprConsent(_ v: Bool) -> Builder { _gdprConsent = v; return self }
        @discardableResult public func doNotTrack(_ v: Bool) -> Builder { _doNotTrack = v; return self }

        public func build() -> IdentifyParams {
            IdentifyParams(
                distinctId: _distinctId,
                externalUserId: _externalUserId,
                firstName: _firstName,
                lastName: _lastName,
                phone: _phone,
                avatar: _avatar,
                locale: _locale,
                language: _language,
                appVersion: _appVersion,
                appBuild: _appBuild,
                traits: _traits,
                utmSource: _utmSource,
                utmMedium: _utmMedium,
                utmCampaign: _utmCampaign,
                utmContent: _utmContent,
                utmTerm: _utmTerm,
                installSource: _installSource,
                installCampaign: _installCampaign,
                emailOptIn: _emailOptIn,
                smsOptIn: _smsOptIn,
                pushOptIn: _pushOptIn,
                gdprConsent: _gdprConsent,
                doNotTrack: _doNotTrack
            )
        }
    }
}
