import Foundation

/// Immutable configuration for the Dyplink SDK.
///
/// Construct via `DyplinkConfig.Builder`:
/// ```swift
/// let config = DyplinkConfig.Builder(
///     baseUrl: "https://api.dyplink.com",
///     apiKey: "your-api-key",
///     projectId: "your-project-id"
/// )
/// .logLevel(.debug)
/// .flushInterval(60)
/// .build()
/// ```
public struct DyplinkConfig: Sendable {
    public let baseUrl: String
    public let apiKey: String
    public let projectId: String
    public let logLevel: DyplinkLogLevel
    public let flushIntervalSeconds: Int
    public let maxQueueSize: Int
    public let maxRetries: Int
    public let sessionTimeoutSeconds: Int
    public let enableAutoSessionTracking: Bool
    public let enableAutoDeviceInfo: Bool
    public let deepLinkHosts: [String]
    public let customScheme: String?

    fileprivate init(
        baseUrl: String,
        apiKey: String,
        projectId: String,
        logLevel: DyplinkLogLevel,
        flushIntervalSeconds: Int,
        maxQueueSize: Int,
        maxRetries: Int,
        sessionTimeoutSeconds: Int,
        enableAutoSessionTracking: Bool,
        enableAutoDeviceInfo: Bool,
        deepLinkHosts: [String],
        customScheme: String?
    ) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.projectId = projectId
        self.logLevel = logLevel
        self.flushIntervalSeconds = flushIntervalSeconds
        self.maxQueueSize = maxQueueSize
        self.maxRetries = maxRetries
        self.sessionTimeoutSeconds = sessionTimeoutSeconds
        self.enableAutoSessionTracking = enableAutoSessionTracking
        self.enableAutoDeviceInfo = enableAutoDeviceInfo
        self.deepLinkHosts = deepLinkHosts
        self.customScheme = customScheme
    }

    /// Fluent builder for `DyplinkConfig`. Mirrors the Android
    /// `DyplinkConfig.Builder`.
    public final class Builder {
        private let baseUrl: String
        private let apiKey: String
        private let projectId: String

        private var _logLevel: DyplinkLogLevel = .none
        private var _flushIntervalSeconds: Int = 30
        private var _maxQueueSize: Int = 1000
        private var _maxRetries: Int = 3
        private var _sessionTimeoutSeconds: Int = 300
        private var _enableAutoSessionTracking: Bool = true
        private var _enableAutoDeviceInfo: Bool = true
        private var _deepLinkHosts: [String] = []
        private var _customScheme: String?

        public init(baseUrl: String, apiKey: String, projectId: String) {
            self.baseUrl = baseUrl
            self.apiKey = apiKey
            self.projectId = projectId
        }

        @discardableResult public func logLevel(_ level: DyplinkLogLevel) -> Builder {
            _logLevel = level; return self
        }

        @discardableResult public func flushInterval(_ seconds: Int) -> Builder {
            _flushIntervalSeconds = seconds; return self
        }

        @discardableResult public func maxQueueSize(_ size: Int) -> Builder {
            _maxQueueSize = size; return self
        }

        @discardableResult public func maxRetries(_ retries: Int) -> Builder {
            _maxRetries = retries; return self
        }

        @discardableResult public func sessionTimeout(_ seconds: Int) -> Builder {
            _sessionTimeoutSeconds = seconds; return self
        }

        @discardableResult public func enableAutoSessionTracking(_ enabled: Bool) -> Builder {
            _enableAutoSessionTracking = enabled; return self
        }

        @discardableResult public func enableAutoDeviceInfo(_ enabled: Bool) -> Builder {
            _enableAutoDeviceInfo = enabled; return self
        }

        @discardableResult public func deepLinkHosts(_ hosts: [String]) -> Builder {
            _deepLinkHosts = hosts; return self
        }

        @discardableResult public func customScheme(_ scheme: String) -> Builder {
            _customScheme = scheme; return self
        }

        /// Validate and build. Throws `DyplinkError.invalidConfig` for
        /// blank required fields or out-of-range numeric values.
        public func build() throws -> DyplinkConfig {
            let trimmedBase = baseUrl.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if trimmedBase.isEmpty {
                throw DyplinkError.invalidConfig("baseUrl must not be blank")
            }
            if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                throw DyplinkError.invalidConfig("apiKey must not be blank")
            }
            if projectId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw DyplinkError.invalidConfig("projectId must not be blank")
            }
            if _flushIntervalSeconds <= 0 {
                throw DyplinkError.invalidConfig("flushInterval must be positive")
            }
            if _maxQueueSize <= 0 {
                throw DyplinkError.invalidConfig("maxQueueSize must be positive")
            }
            if _maxRetries < 0 {
                throw DyplinkError.invalidConfig("maxRetries must be non-negative")
            }

            return DyplinkConfig(
                baseUrl: trimmedBase,
                apiKey: apiKey,
                projectId: projectId,
                logLevel: _logLevel,
                flushIntervalSeconds: _flushIntervalSeconds,
                maxQueueSize: _maxQueueSize,
                maxRetries: _maxRetries,
                sessionTimeoutSeconds: _sessionTimeoutSeconds,
                enableAutoSessionTracking: _enableAutoSessionTracking,
                enableAutoDeviceInfo: _enableAutoDeviceInfo,
                deepLinkHosts: _deepLinkHosts,
                customScheme: _customScheme
            )
        }
    }
}
