import Foundation

/// Main entry point for the Dyplink iOS SDK.
///
/// Initialize once during app launch — typically in
/// `application(_:didFinishLaunchingWithOptions:)`:
/// ```swift
/// let config = try DyplinkConfig.Builder(
///     baseUrl: "https://api.dyplink.com",
///     apiKey: "your-api-key",
///     projectId: "your-project-id"
/// ).logLevel(.debug).build()
///
/// Dyplink.shared.initialize(config: config)
/// ```
///
/// All public methods are thread-safe.
public final class Dyplink: @unchecked Sendable {

    /// Shared singleton. Mirrors `Dyplink` on Android.
    public static let shared = Dyplink()

    private let lock = NSLock()
    private var _isInitialized = false

    // Internal components — populated by `initialize(config:)`.
    private var config: DyplinkConfig?
    private var preferences: DyplinkPreferences?
    private var fingerprintProvider: FingerprintProvider?
    private var identityManager: IdentityManager?
    private var eventTracker: EventTracker?
    private var conversionTracker: ConversionTracker?
    private var queueManager: EventQueueManager?
    private var deferredMatcher: DeferredDeepLinkMatcher?
    private var universalLinkParser: UniversalLinkParser?
    private var connectivityMonitor: ConnectivityMonitor?
    private var lifecycleObserver: AppLifecycleObserver?
    private var sessionTracker: SessionTracker?

    /// Closure-based deep link listener. Alternative to `deepLinkListener`
    /// below — the SDK invokes whichever is set.
    public var onDeepLink: (@Sendable (DeepLinkResult) -> Void)?

    /// Protocol-based deep link listener (weak reference).
    public weak var deepLinkListener: DeepLinkListener?

    private init() {}

    // ── Lifecycle ──────────────────────────────────────────────────────

    /// `true` when `initialize(config:)` has been called successfully.
    public var isInitialized: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isInitialized
    }

    /// Initialize the SDK. Safe to call more than once — subsequent
    /// calls log a warning and return.
    public func initialize(config: DyplinkConfig) {
        lock.lock()
        if _isInitialized {
            lock.unlock()
            DyplinkLogger.w("Dyplink already initialized, ignoring duplicate initialize()")
            return
        }

        DyplinkLogger.logLevel = config.logLevel
        self.config = config

        // Bridge globals
        DyplinkConfigBridge.baseUrl = config.baseUrl
        DyplinkConfigBridge.apiKey = config.apiKey
        DyplinkConfigBridge.projectId = config.projectId

        // Storage
        let preferences = DyplinkPreferences()
        self.preferences = preferences

        // Network
        let apiClient = ApiClient(config: config)
        let requestExecutor = RequestExecutor(
            apiClient: apiClient,
            baseUrl: config.baseUrl,
            maxRetries: config.maxRetries
        )

        // Identity
        let fingerprintProvider = FingerprintProvider(preferences: preferences)
        let deviceInfoCollector = DeviceInfoCollector()
        self.fingerprintProvider = fingerprintProvider

        DyplinkConfigBridge.deviceFingerprint = fingerprintProvider.fingerprint
        DyplinkConfigBridge.distinctId = fingerprintProvider.distinctId

        identityManager = IdentityManager(
            requestExecutor: requestExecutor,
            fingerprintProvider: fingerprintProvider,
            deviceInfoCollector: deviceInfoCollector,
            projectId: config.projectId,
            enableAutoDeviceInfo: config.enableAutoDeviceInfo
        )

        // Queue
        let store = EventQueueStore()
        let queueManager = EventQueueManager(
            store: store,
            requestExecutor: requestExecutor,
            maxQueueSize: config.maxQueueSize,
            maxRetries: config.maxRetries,
            flushIntervalSeconds: config.flushIntervalSeconds
        )
        queueManager.start()
        self.queueManager = queueManager

        // Connectivity — trigger flush on reconnect.
        let connectivityMonitor = ConnectivityMonitor()
        connectivityMonitor.addListener { [weak queueManager] in
            queueManager?.triggerFlush()
        }
        connectivityMonitor.start()
        self.connectivityMonitor = connectivityMonitor

        // Tracking
        eventTracker = EventTracker(
            queueManager: queueManager,
            fingerprintProvider: fingerprintProvider,
            projectId: config.projectId
        )
        conversionTracker = ConversionTracker(
            queueManager: queueManager,
            preferences: preferences,
            projectId: config.projectId
        )

        // Deep linking
        universalLinkParser = UniversalLinkParser(
            deepLinkHosts: config.deepLinkHosts,
            customScheme: config.customScheme
        )
        deferredMatcher = DeferredDeepLinkMatcher(
            requestExecutor: requestExecutor,
            deviceInfoCollector: deviceInfoCollector,
            preferences: preferences
        )

        // Lifecycle + sessions
        if config.enableAutoSessionTracking, let et = eventTracker {
            let sessionTracker = SessionTracker(
                eventTracker: et,
                preferences: preferences,
                sessionTimeoutSeconds: config.sessionTimeoutSeconds
            )
            self.sessionTracker = sessionTracker

            let lifecycleObserver = AppLifecycleObserver(
                queueManager: queueManager,
                sessionTracker: sessionTracker,
                connectivityMonitor: connectivityMonitor
            )
            lifecycleObserver.start()
            self.lifecycleObserver = lifecycleObserver
        }

        _isInitialized = true
        lock.unlock()

        DyplinkLogger.i("Dyplink SDK initialized (project=\(config.projectId))")

        // Fire initial anonymous identify (fire-and-forget).
        Task { [weak self] in
            guard let self = self, let im = self.identityManager else { return }
            do {
                _ = try await im.identify(IdentifyParams.Builder().build())
            } catch {
                DyplinkLogger.e("Initial identify failed", error)
            }
        }
    }

    // ── Identity accessors ─────────────────────────────────────────────

    /// The current distinct ID (anonymous or identified).
    public var distinctId: String {
        try? checkInitialized()
        return fingerprintProvider?.distinctId ?? ""
    }

    /// Stable device fingerprint UUID.
    public var deviceFingerprint: String {
        try? checkInitialized()
        return fingerprintProvider?.fingerprint ?? ""
    }

    // ── Public API ─────────────────────────────────────────────────────

    /// Identify the current user. Throws `DyplinkError` on failure.
    @discardableResult
    public func identify(_ params: IdentifyParams) async throws -> IdentifyResult {
        try checkInitialized()
        guard let im = identityManager else {
            throw DyplinkError.notInitialized()
        }
        let result = try await im.identify(params)
        DyplinkConfigBridge.distinctId = fingerprintProvider?.distinctId ?? ""
        return result
    }

    /// Track a custom event. Fire-and-forget.
    public func track(_ eventName: String, properties: [String: Any]? = nil) {
        try? checkInitialized()
        eventTracker?.track(eventName, properties: properties)
    }

    /// Track a conversion event.
    public func trackConversion(_ params: TrackConversionParams) {
        try? checkInitialized()
        conversionTracker?.trackConversion(params)
    }

    /// Track a revenue event.
    public func trackRevenue(_ amount: Double, currency: String = "USD") {
        try? checkInitialized()
        conversionTracker?.trackRevenue(amount: amount, currency: currency)
    }

    /// Parse an incoming deep-link URL and notify listeners.
    ///
    /// Call from `scene(_:continue:)` (Universal Links) and
    /// `application(_:open:options:)` (custom URL scheme).
    ///
    /// Returns the parsed `DeepLinkResult`, or `nil` if the URL is not
    /// a recognized Dyplink link.
    @discardableResult
    public func handleDeepLink(url: URL) -> DeepLinkResult? {
        try? checkInitialized()
        guard let result = universalLinkParser?.parse(url) else { return nil }

        // Notify listeners
        onDeepLink?(result)
        if let listener = deepLinkListener {
            listener.dyplink(self, didReceive: result)
        }

        // Auto-track the open
        track("deep_link_opened", properties: [
            "url": result.url,
            "short_code": result.shortCode ?? "",
            "is_deferred": result.isDeferred,
        ])

        return result
    }

    /// Attempt a deferred deep link match against the Dyplink backend.
    /// The match is attempted at most once per install.
    @discardableResult
    public func matchDeferredDeepLink() async -> DeferredMatchResult {
        try? checkInitialized()
        guard let matcher = deferredMatcher else { return .unmatched }
        let result = await matcher.match()

        // Forward to deep-link listeners when matched
        if result.matched {
            let deepLinkResult = DeepLinkResult(
                url: "",
                shortCode: result.shortCode,
                params: result.params,
                isDeferred: true,
                linkId: result.linkId
            )
            onDeepLink?(deepLinkResult)
            if let listener = deepLinkListener {
                listener.dyplink(self, didReceive: deepLinkResult)
            }
        }
        return result
    }

    /// The attributed short code from the most recent deferred match, if any.
    public func getAttributedShortCode() -> String? {
        preferences?.attributedShortCode
    }

    /// The attributed link ID from the most recent deferred match, if any.
    public func getAttributedLinkId() -> String? {
        preferences?.attributedLinkId
    }

    /// Reset identity. Call on user logout — generates a fresh
    /// anonymous ID. Device fingerprint is unaffected.
    public func reset() {
        try? checkInitialized()
        fingerprintProvider?.reset()
        DyplinkConfigBridge.distinctId = fingerprintProvider?.distinctId ?? ""
        DyplinkLogger.i("Identity reset — new anonymous ID: \(fingerprintProvider?.anonymousId ?? "?")")
    }

    /// Immediately flush all queued events.
    public func flush() async {
        try? checkInitialized()
        await queueManager?.flush()
    }

    // ── Internal helpers ───────────────────────────────────────────────

    private func checkInitialized() throws {
        lock.lock(); defer { lock.unlock() }
        if !_isInitialized {
            throw DyplinkError.notInitialized()
        }
    }

    /// Test-only hook that resets the singleton state.
    internal func resetForTesting() {
        lock.lock()
        _isInitialized = false
        config = nil
        preferences = nil
        fingerprintProvider = nil
        identityManager = nil
        eventTracker = nil
        conversionTracker = nil
        queueManager?.stop()
        queueManager = nil
        deferredMatcher = nil
        universalLinkParser = nil
        connectivityMonitor?.stop()
        connectivityMonitor = nil
        lifecycleObserver?.stop()
        lifecycleObserver = nil
        sessionTracker = nil
        lock.unlock()
    }
}
