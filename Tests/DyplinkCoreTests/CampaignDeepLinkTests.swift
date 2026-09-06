import XCTest
@testable import DyplinkCore

/// Covers `handleCampaignDeepLink(url:)` — the entry point for destination
/// URLs that arrive out of band, such as the one a push campaign carries —
/// and the `nil` contract of `handleDeepLink(url:)` it deliberately breaks
/// with.
final class CampaignDeepLinkTests: XCTestCase {

    /// Collects the results handed to `onDeepLink`, which the SDK may invoke
    /// from any thread.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _results: [DeepLinkResult] = []

        var results: [DeepLinkResult] {
            lock.lock(); defer { lock.unlock() }
            return _results
        }

        func record(_ result: DeepLinkResult) {
            lock.lock(); defer { lock.unlock() }
            _results.append(result)
        }
    }

    private final class ListenerSpy: DeepLinkListener {
        private(set) var received: [DeepLinkResult] = []

        func dyplink(_ dyplink: Dyplink, didReceive result: DeepLinkResult) {
            received.append(result)
        }
    }

    private var recorder: Recorder!
    private var listener: ListenerSpy!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let config = try DyplinkConfig.Builder(
            // Nothing should reach the network; a refused port fails fast.
            baseUrl: "http://127.0.0.1:9",
            apiKey: "k",
            projectId: "p"
        )
        .deepLinkHosts(["dyp.link"])
        .customScheme("dyplinkdemo")
        .enableAutoSessionTracking(false)
        .flushInterval(3600)
        .build()

        Dyplink.shared.initialize(config: config)

        let recorder = Recorder()
        let listener = ListenerSpy()
        self.recorder = recorder
        self.listener = listener
        Dyplink.shared.onDeepLink = { recorder.record($0) }
        Dyplink.shared.deepLinkListener = listener
    }

    override func tearDown() {
        Dyplink.shared.onDeepLink = nil
        Dyplink.shared.deepLinkListener = nil
        Dyplink.shared.resetForTesting()
        recorder = nil
        listener = nil
        super.tearDown()
    }

    func testParsesDyplinkShortLinkIntoFullResult() throws {
        let url = try XCTUnwrap(URL(string: "https://dyp.link/abc123?utm_source=push"))

        let result = Dyplink.shared.handleCampaignDeepLink(url: url)

        XCTAssertEqual(result.url, "https://dyp.link/abc123?utm_source=push")
        XCTAssertEqual(result.shortCode, "abc123")
        XCTAssertEqual(result.params?["utm_source"], AnyJSONValue("push"))
        XCTAssertFalse(result.isDeferred)
    }

    func testPassesThroughPlainAppURLInsteadOfDroppingIt() throws {
        let url = try XCTUnwrap(URL(string: "myapp://product/42"))

        let result = Dyplink.shared.handleCampaignDeepLink(url: url)

        XCTAssertEqual(result.url, "myapp://product/42")
        XCTAssertNil(result.shortCode)
        XCTAssertNil(result.params)
        XCTAssertFalse(result.isDeferred)
    }

    func testPassesThroughWebURLOnAnUnconfiguredHost() throws {
        let url = try XCTUnwrap(URL(string: "https://shop.example.com/sale?id=7"))

        let result = Dyplink.shared.handleCampaignDeepLink(url: url)

        XCTAssertEqual(result.url, "https://shop.example.com/sale?id=7")
        XCTAssertNil(result.shortCode)
    }

    func testNotifiesBothListenerKinds() throws {
        let shortLink = try XCTUnwrap(URL(string: "https://dyp.link/abc123"))
        let appLink = try XCTUnwrap(URL(string: "myapp://product/42"))

        let parsed = Dyplink.shared.handleCampaignDeepLink(url: shortLink)
        let passedThrough = Dyplink.shared.handleCampaignDeepLink(url: appLink)

        XCTAssertEqual(recorder.results, [parsed, passedThrough])
        XCTAssertEqual(listener.received, [parsed, passedThrough])
    }

    /// `handleDeepLink(url:)` must keep dropping URLs it doesn't recognize:
    /// Universal Link callers read `nil` as "not ours, leave it alone".
    func testHandleDeepLinkStillReturnsNilForUnrecognizedURL() throws {
        let url = try XCTUnwrap(URL(string: "https://shop.example.com/sale"))

        XCTAssertNil(Dyplink.shared.handleDeepLink(url: url))
        XCTAssertTrue(recorder.results.isEmpty)
        XCTAssertTrue(listener.received.isEmpty)
    }

    func testHandleDeepLinkStillNotifiesForRecognizedURL() throws {
        let url = try XCTUnwrap(URL(string: "dyplinkdemo://open/abc123"))

        let result = try XCTUnwrap(Dyplink.shared.handleDeepLink(url: url))

        XCTAssertEqual(result.shortCode, "abc123")
        XCTAssertEqual(recorder.results, [result])
        XCTAssertEqual(listener.received, [result])
    }
}
