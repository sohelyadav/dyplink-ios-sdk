import XCTest
import UserNotifications
@testable import DyplinkCore
@testable import DyplinkPush

/// Covers what a press on one of a campaign's buttons reports and where it
/// leads.
///
/// Android sends the pressed button's id as `metadata.actionId`, and the
/// server stores it on the event so a report can tell "pressed Buy now" from
/// "tapped the notification". iOS sent no action id at all — it had no way
/// to know one had been pressed — so even once the buttons are drawn, every
/// press would have been indistinguishable from a tap on the notification.
final class PushActionReportingTests: XCTestCase {

    /// Collects the results handed to `onDeepLink`, which the SDK may invoke
    /// from any thread.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _urls: [String] = []

        var urls: [String] {
            lock.lock(); defer { lock.unlock() }
            return _urls
        }

        func record(_ url: String) {
            lock.lock(); defer { lock.unlock() }
            _urls.append(url)
        }
    }

    private var recorder: Recorder!

    private let actionsJson = #"""
    [{"id":"buy_now","title":"Buy now","deepLinkUrl":"myapp://cart"},
     {"id":"later","title":"Remind me later"}]
    """#

    private func payload(campaignId: String) -> [AnyHashable: Any] {
        [
            "dyplink_campaign_id": campaignId,
            "deep_link_url": "myapp://home",
            "dyplink_actions": actionsJson,
        ]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        Dyplink.shared.resetForTesting()

        let config = try DyplinkConfig.Builder(
            // Nothing should reach the network; a refused port fails fast,
            // and the stub intercepts what matters.
            baseUrl: "http://127.0.0.1:9",
            apiKey: "k",
            projectId: "p"
        )
        .enableAutoSessionTracking(false)
        .flushInterval(3600)
        .build()

        Dyplink.shared.initialize(config: config)
        DyplinkPush.shared.initialize()

        let recorder = Recorder()
        self.recorder = recorder
        Dyplink.shared.onDeepLink = { recorder.record($0.url) }
    }

    override func tearDown() {
        StubURLProtocol.stopIntercepting()
        Dyplink.shared.onDeepLink = nil
        DyplinkPush.shared.resetForTesting()
        Dyplink.shared.resetForTesting()
        recorder = nil
        super.tearDown()
    }

    /// The reported event body for `campaignId`. Reports are
    /// fire-and-forget, so one from an earlier test can still be in flight —
    /// match on the campaign id rather than the first request that turns up.
    private func reportedEvent(
        campaignId: String,
        _ work: () -> Void
    ) throws -> [String: Any] {
        let reported = expectation(description: "push event posted")
        let captured = ActionBox<[String: Any]?>(nil)

        StubURLProtocol.startIntercepting { request in
            guard request.url?.path == "/api/push-notifications/events",
                  let body = request.interceptedBody,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  json["campaignId"] as? String == campaignId
            else { return }

            captured.value = json
            reported.fulfill()
        }

        work()
        wait(for: [reported], timeout: 5)
        return try XCTUnwrap(captured.value)
    }

    // ── Reporting ──────────────────────────────────────────────────────

    func testAButtonPressReportsItsActionId() throws {
        let json = try reportedEvent(campaignId: "camp-action") {
            DyplinkPush.shared.reportNotificationClicked(
                userInfo: payload(campaignId: "camp-action"),
                actionIdentifier: "buy_now"
            )
        }

        XCTAssertEqual(json["type"] as? String, "click")
        let metadata = try XCTUnwrap(json["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["actionId"] as? String, "buy_now")
    }

    /// `UNNotificationDefaultActionIdentifier` is iOS saying "the
    /// notification itself was tapped". Reported as an action id it would
    /// invent a button called
    /// `com.apple.UNNotificationDefaultActionIdentifier` in every campaign's
    /// per-action breakdown.
    func testTappingTheNotificationItselfReportsNoActionId() throws {
        let json = try reportedEvent(campaignId: "camp-body") {
            DyplinkPush.shared.reportNotificationClicked(
                userInfo: payload(campaignId: "camp-body"),
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )
        }

        XCTAssertEqual(json["type"] as? String, "click")
        XCTAssertNil(json["metadata"])
    }

    func testAPlainClickStillReportsNoActionId() throws {
        let json = try reportedEvent(campaignId: "camp-plain") {
            DyplinkPush.shared.reportNotificationClicked(userInfo: self.payload(campaignId: "camp-plain"))
        }

        XCTAssertNil(json["metadata"])
    }

    // ── Routing ────────────────────────────────────────────────────────

    /// A button's own destination wins over the campaign's — the order
    /// Android's `PushNotificationHandler` builds its action intents in.
    func testAButtonsOwnDestinationIsRouted() {
        let returned = DyplinkPush.shared.reportNotificationClicked(
            userInfo: payload(campaignId: "camp-1"),
            actionIdentifier: "buy_now"
        )

        XCTAssertEqual(returned, "myapp://cart")
        XCTAssertEqual(recorder.urls, ["myapp://cart"])
    }

    func testAButtonWithNoDestinationFallsBackToTheCampaigns() {
        let returned = DyplinkPush.shared.reportNotificationClicked(
            userInfo: payload(campaignId: "camp-2"),
            actionIdentifier: "later"
        )

        XCTAssertEqual(returned, "myapp://home")
        XCTAssertEqual(recorder.urls, ["myapp://home"])
    }

    func testAnUnknownActionIdFallsBackToTheCampaignsDestination() {
        let returned = DyplinkPush.shared.reportNotificationClicked(
            userInfo: payload(campaignId: "camp-3"),
            actionIdentifier: "not_a_button"
        )

        XCTAssertEqual(returned, "myapp://home")
    }

    /// Tapping the notification itself routes the campaign's destination,
    /// exactly as it did before buttons existed.
    func testTappingTheNotificationItselfStillRoutesTheCampaignsDestination() {
        let returned = DyplinkPush.shared.reportNotificationClicked(
            userInfo: payload(campaignId: "camp-4"),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertEqual(returned, "myapp://home")
    }
}

/// Lets a test read a value written from the URL loading system's thread.
private final class ActionBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
