import Foundation

/// Result returned from a successful `Dyplink.shared.identify` call.
public struct IdentifyResult: Sendable, Equatable {
    public let id: String
    public let projectId: String
    public let distinctId: String?
    public let externalUserId: String?
    public let deviceFingerprint: String
    public let platform: String

    public init(
        id: String,
        projectId: String,
        distinctId: String? = nil,
        externalUserId: String? = nil,
        deviceFingerprint: String,
        platform: String
    ) {
        self.id = id
        self.projectId = projectId
        self.distinctId = distinctId
        self.externalUserId = externalUserId
        self.deviceFingerprint = deviceFingerprint
        self.platform = platform
    }
}
