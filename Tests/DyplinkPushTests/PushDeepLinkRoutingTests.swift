import XCTest
@testable import DyplinkCore
@testable import DyplinkPush

/// Covers the deep link a push campaign carries: which payload keys it is
/// read from, and that reporting the click and routing the link stay
/// independent of one another.
final class PushDeepLinkRoutingTests: XCTestCase {

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

    private var recorder: Recorder!

    override func setUpWithError() throws {
        try super.setUpWithError()

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
        DyplinkPush.shared.initialize()

        let recorder = Recorder()
        self.recorder = recorder
        Dyplink.shared.onDeepLink = { recorder.record($0) }
    }

    override func tearDown() {
        StubURLProtocol.stopIntercepting()
        Dyplink.shared.onDeepLink = nil
        DyplinkPush.shared.resetForTesting()
        Dyplink.shared.resetForTesting()
        recorder = nil
        super.tearDown()
    }

    // ── Routing ────────────────────────────────────────────────────────

    func testRoutesDyplinkShortLinkAsAFullResult() {
        let url = "https://dyp.link/abc123?utm_source=push"

        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": "camp-1",
            "deep_link_url": url,
        ])

        XCTAssertEqual(returned, url)
        XCTAssertEqual(recorder.results.count, 1)
        XCTAssertEqual(recorder.results.first?.url, url)
        XCTAssertEqual(recorder.results.first?.shortCode, "abc123")
        XCTAssertEqual(recorder.results.first?.params?["utm_source"], AnyJSONValue("push"))
    }

    /// The destination is usually not a Dyplink link at all. Android opens
    /// whatever the campaign sent, so these must not be dropped.
    func testRoutesPlainAppURLThatTheParserDoesNotRecognize() {
        let url = "myapp://product/42"

        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": "camp-2",
            "deep_link_url": url,
        ])

        XCTAssertEqual(returned, url)
        XCTAssertEqual(recorder.results.count, 1)
        XCTAssertEqual(recorder.results.first?.url, url)
        XCTAssertNil(recorder.results.first?.shortCode)
        XCTAssertEqual(recorder.results.first?.isDeferred, false)
    }

    func testFallsBackToTheLinkKey() {
        let url = "https://shop.example.com/sale"

        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": "camp-3",
            "link": url,
        ])

        XCTAssertEqual(returned, url)
        XCTAssertEqual(recorder.results.map(\.url), [url])
    }

    /// Same precedence as Android's `PushNotificationHandler`.
    func testDeepLinkUrlKeyWinsOverLinkKey() {
        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": "camp-4",
            "deep_link_url": "myapp://wins",
            "link": "myapp://loses",
        ])

        XCTAssertEqual(returned, "myapp://wins")
        XCTAssertEqual(recorder.results.map(\.url), ["myapp://wins"])
    }

    func testPayloadWithoutADeepLinkRoutesNothing() {
        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": "camp-5",
            "title": "Hello",
        ])

        XCTAssertNil(returned)
        XCTAssertTrue(recorder.results.isEmpty)
    }

    /// `userInfo` arrives from the OS untyped and can hold anything.
    func testIgnoresDeepLinkValuesThatAreNotUsableStrings() {
        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": "camp-6",
            "deep_link_url": 42,
            "link": "   ",
        ])

        XCTAssertNil(returned)
        XCTAssertTrue(recorder.results.isEmpty)
    }

    /// Routing does not depend on the push being a Dyplink campaign, just as
    /// on Android the tap intent is built whether or not a campaign id is set.
    func testRoutesEvenWhenThereIsNoCampaignIdToReport() {
        let returned = DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "deep_link_url": "myapp://product/42",
        ])

        XCTAssertEqual(returned, "myapp://product/42")
        XCTAssertEqual(recorder.results.map(\.url), ["myapp://product/42"])
    }

    // ── Reporting ──────────────────────────────────────────────────────

    /// The other half of the same independence: a payload with no deep link
    /// still reports the click.
    func testReportsTheClickWhenThereIsNoDeepLink() throws {
        let campaignId = "camp-7"
        let reported = expectation(description: "click event posted")
        let captured = UncheckedBox<[String: Any]?>(nil)

        // Reports are fire-and-forget, so one from an earlier test can still
        // be in flight — match on this campaign id rather than the first
        // request that turns up.
        StubURLProtocol.startIntercepting { request in
            guard request.url?.path == "/api/push-notifications/events",
                  let body = request.interceptedBody,
                  let object = try? JSONSerialization.jsonObject(with: body),
                  let json = object as? [String: Any],
                  json["campaignId"] as? String == campaignId
            else { return }

            captured.value = json
            reported.fulfill()
        }

        DyplinkPush.shared.reportNotificationClicked(userInfo: [
            "dyplink_campaign_id": campaignId,
        ])

        wait(for: [reported], timeout: 5)

        let json = try XCTUnwrap(captured.value)
        XCTAssertEqual(json["type"] as? String, "click")
        XCTAssertEqual(json["platform"] as? String, "ios")
    }
}

/// Lets a test observe a value written from the URL loading system's thread.
private final class UncheckedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
