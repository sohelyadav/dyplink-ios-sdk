import XCTest
@testable import DyplinkCore

/// Covers where a `cookieRef` comes from on iOS.
///
/// Android reads one from the Play Install Referrer. iOS has no equivalent,
/// which is why the deferred match never sent one — but "no install
/// referrer" is not "no short code ever": a Universal Link opened before the
/// match has run carries one, and a host app that moved the code across its
/// own web-to-app handoff can supply it.
final class DeferredCookieRefTests: XCTestCase {

    /// The suite `Dyplink.initialize` builds its own preferences from.
    private var preferences: DyplinkPreferences!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // `initialize` is a no-op on an already-initialized singleton, and
        // this one is shared with every other test in the bundle.
        Dyplink.shared.resetForTesting()

        let config = try DyplinkConfig.Builder(
            // Nothing should reach the network; a refused port fails fast.
            baseUrl: "http://127.0.0.1:9",
            apiKey: "k",
            projectId: "p"
        )
        .deepLinkHosts(["dyp.link"])
        .enableAutoSessionTracking(false)
        .flushInterval(3600)
        .build()

        Dyplink.shared.initialize(config: config)
        preferences = DyplinkPreferences()
        preferences.pendingCookieRef = nil
        preferences.deferredMatchAttempted = false
    }

    override func tearDown() {
        preferences.pendingCookieRef = nil
        preferences.deferredMatchAttempted = false
        Dyplink.shared.resetForTesting()
        super.tearDown()
    }

    func testAShortCodeFromAUniversalLinkIsKeptForTheMatch() throws {
        Dyplink.shared.handleDeepLink(url: try XCTUnwrap(URL(string: "https://dyp.link/abc123")))

        XCTAssertEqual(preferences.pendingCookieRef, "abc123")
    }

    func testAHostAppCanSupplyOneItself() {
        Dyplink.shared.setDeferredCookieRef("xyz789")

        XCTAssertEqual(preferences.pendingCookieRef, "xyz789")
    }

    /// A URL with no short code in it leaves whatever was there alone — it
    /// has nothing better to offer.
    func testAURLWithNoShortCodeKeepsNothing() throws {
        Dyplink.shared.handleCampaignDeepLink(url: try XCTUnwrap(URL(string: "myapp://product/42")))

        XCTAssertNil(preferences.pendingCookieRef)
    }

    /// The match happens once per install. A code kept past it would be sent
    /// on a match that can no longer happen.
    func testNothingIsKeptOnceTheMatchHasRun() throws {
        preferences.deferredMatchAttempted = true

        Dyplink.shared.handleDeepLink(url: try XCTUnwrap(URL(string: "https://dyp.link/abc123")))
        Dyplink.shared.setDeferredCookieRef("xyz789")

        XCTAssertNil(preferences.pendingCookieRef)
    }
}

/// Covers the diagnostic channel the optional modules report through.
///
/// Every swallowed failure in Push, Banners and Messages had nowhere to go:
/// `DyplinkLogger` is internal to `DyplinkCore`, so the modules that need it
/// most could not reach it, and `_ = try? await …` was the result. It is off
/// unless the host app asks for it, which is the other half of why this is
/// safe to add.
final class DiagnosticsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Same reason as above: `initialize` does nothing to a singleton
        // that is already initialized, including to its log level.
        Dyplink.shared.resetForTesting()
    }

    override func tearDown() {
        Dyplink.shared.resetForTesting()
        DyplinkLogger.logLevel = .none
        super.tearDown()
    }

    func testTheChannelIsSilentUntilTheHostAppAsksForIt() throws {
        DyplinkLogger.logLevel = .none

        let config = try DyplinkConfig.Builder(baseUrl: "http://127.0.0.1:9", apiKey: "k", projectId: "p")
            .enableAutoSessionTracking(false)
            .flushInterval(3600)
            .build()

        XCTAssertEqual(config.logLevel, .none, "diagnostics must be off by default")
        Dyplink.shared.initialize(config: config)
        XCTAssertEqual(DyplinkLogger.logLevel, .none)
    }

    func testTheConfiguredLevelReachesTheLogger() throws {
        let config = try DyplinkConfig.Builder(baseUrl: "http://127.0.0.1:9", apiKey: "k", projectId: "p")
            .logLevel(.debug)
            .enableAutoSessionTracking(false)
            .flushInterval(3600)
            .build()

        Dyplink.shared.initialize(config: config)

        XCTAssertEqual(DyplinkLogger.logLevel, .debug)
    }

    /// The optional modules call these from fire-and-forget paths, where a
    /// throw or a trap would cost the user the notification or the message
    /// the report belongs to.
    func testReportingAFailureNeverThrowsOrTraps() {
        DyplinkLogger.logLevel = .verbose

        DyplinkDiagnostics.httpFailure("GET /test", statusCode: 401, body: Data(#"{"m":"nope"}"#.utf8))
        DyplinkDiagnostics.httpFailure("GET /test", statusCode: 500, body: nil)
        DyplinkDiagnostics.httpFailure("GET /test", statusCode: 500, body: Data())
        // Not UTF-8, and a body far longer than anything worth logging.
        DyplinkDiagnostics.httpFailure("GET /test", statusCode: 500, body: Data([0xFF, 0xFE, 0x00]))
        DyplinkDiagnostics.httpFailure(
            "GET /test",
            statusCode: 500,
            body: Data(String(repeating: "x", count: 10_000).utf8)
        )
        DyplinkDiagnostics.transportFailure("GET /test", URLError(.notConnectedToInternet))
        DyplinkDiagnostics.warn("warned")
        DyplinkDiagnostics.error("failed", DyplinkError.notInitialized())
        DyplinkDiagnostics.debug("detail")
    }
}
