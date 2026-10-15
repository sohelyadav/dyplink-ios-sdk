import XCTest
@testable import DyplinkCore

/// Covers the body `POST /api/conversions` is sent, which the server
/// rejected outright.
///
/// Two things were wrong and the second hid behind the first. `shortCode`
/// and `linkId` were sent as JSON `null` when absent, and a conversion with
/// neither is a `400 Either shortCode or linkId must be provided` — then
/// `EventQueueManager` treats a 4xx as final and deletes the event, so every
/// unattributable conversion was queued, refused and discarded with nothing
/// said to the host app.
final class ConversionTrackerTests: XCTestCase {

    private var tempDir: URL!
    private var store: EventQueueStore!
    private var preferences: DyplinkPreferences!
    private var tracker: ConversionTracker!

    override func setUpWithError() throws {
        try super.setUpWithError()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = EventQueueStore(directory: tempDir)

        let config = try DyplinkConfig.Builder(
            // Nothing is flushed — the queue manager is never started — and
            // a refused port fails fast if anything ever were.
            baseUrl: "http://127.0.0.1:9",
            apiKey: "k",
            projectId: "project-1"
        ).build()

        let queueManager = EventQueueManager(
            store: store,
            requestExecutor: RequestExecutor(
                apiClient: ApiClient(config: config),
                baseUrl: config.baseUrl,
                maxRetries: 0
            ),
            maxQueueSize: 100,
            maxRetries: 0,
            flushIntervalSeconds: 3600
        )

        // A suite of its own per test, so one test's attributed link is not
        // the next one's.
        preferences = DyplinkPreferences(suiteName: "com.dyplink.sdk.tests.\(UUID().uuidString)")
        tracker = ConversionTracker(
            queueManager: queueManager,
            preferences: preferences,
            projectId: "project-1"
        )
    }

    override func tearDown() {
        preferences.clear()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// The body of the one queued event, parsed.
    private func queuedBody() throws -> [String: Any] {
        let batch = store.getNextBatch()
        XCTAssertEqual(batch.count, 1, "expected exactly one queued event")
        let entry = try XCTUnwrap(batch.first)
        XCTAssertEqual(entry.endpoint, "/api/conversions")
        return try JSONUtils.decodeObject(Data(entry.payload.utf8))
    }

    // ── Nothing to attribute it to ─────────────────────────────────────

    /// Refused where there is still something to say about it, rather than
    /// queued for a 400 that deletes it silently.
    func testAConversionWithNothingToAttributeItToIsNotQueued() {
        tracker.trackConversion(TrackConversionParams(eventType: "purchase"))

        XCTAssertEqual(store.count(), 0)
    }

    // ── Absent, not null ───────────────────────────────────────────────

    func testAnAbsentLinkIdIsOmittedRatherThanSentAsNull() throws {
        tracker.trackConversion(TrackConversionParams(eventType: "signup", shortCode: "abc123"))

        let body = try queuedBody()
        XCTAssertEqual(body["shortCode"] as? String, "abc123")
        XCTAssertFalse(body.keys.contains("linkId"), "sent linkId: null")
        XCTAssertEqual(body["eventType"] as? String, "signup")
        XCTAssertEqual(body["projectId"] as? String, "project-1")
    }

    func testAnAbsentShortCodeIsOmittedRatherThanSentAsNull() throws {
        let linkId = "7a1d6e52-0000-4000-8000-000000000001"
        tracker.trackConversion(TrackConversionParams(eventType: "purchase", linkId: linkId))

        let body = try queuedBody()
        XCTAssertEqual(body["linkId"] as? String, linkId)
        XCTAssertFalse(body.keys.contains("shortCode"), "sent shortCode: null")
    }

    /// `null` for either key is not "not supplied": the DTO types them as a
    /// string and a UUID, and the service refuses the pair outright.
    func testNeitherKeyIsEverSentAsNull() throws {
        preferences.attributedShortCode = "abc123"
        tracker.trackConversion(TrackConversionParams(eventType: "purchase"))

        let body = try queuedBody()
        for key in ["shortCode", "linkId", "externalUserId", "metadata"] {
            XCTAssertFalse(body[key] is NSNull, "\(key) was sent as null")
        }
    }

    // ── The deferred match's attribution ───────────────────────────────

    func testTheShortCodeFromADeferredMatchIsUsedWhenNoneIsPassed() throws {
        preferences.attributedShortCode = "deferred1"

        tracker.trackConversion(TrackConversionParams(eventType: "purchase"))

        XCTAssertEqual(try queuedBody()["shortCode"] as? String, "deferred1")
    }

    func testAnExplicitShortCodeWinsOverTheStoredOne() throws {
        preferences.attributedShortCode = "deferred1"

        tracker.trackConversion(TrackConversionParams(eventType: "purchase", shortCode: "explicit1"))

        XCTAssertEqual(try queuedBody()["shortCode"] as? String, "explicit1")
    }

    // ── The rest of the body ───────────────────────────────────────────

    func testEverythingElseTheCallerSuppliedIsCarried() throws {
        tracker.trackConversion(TrackConversionParams(
            eventType: "purchase",
            shortCode: "abc123",
            externalUserId: "user-7",
            metadata: ["amount": 42, "currency": "USD"]
        ))

        let body = try queuedBody()
        XCTAssertEqual(body["externalUserId"] as? String, "user-7")
        let metadata = try XCTUnwrap(body["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["amount"] as? Int, 42)
        XCTAssertEqual(metadata["currency"] as? String, "USD")
    }

    /// Revenue is a different endpoint with a different contract — it is
    /// keyed on the device fingerprint, not on a link — so it must keep
    /// working for a device with no attributed link at all.
    func testRevenueIsQueuedWithoutAnyAttributedLink() throws {
        tracker.trackRevenue(amount: 9.99, currency: "EUR")

        let batch = store.getNextBatch()
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(try XCTUnwrap(batch.first).endpoint, "/api/identity/revenue")
    }
}
