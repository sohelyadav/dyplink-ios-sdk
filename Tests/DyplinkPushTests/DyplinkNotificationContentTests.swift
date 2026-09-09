import XCTest
import UIKit
import UserNotifications
@testable import DyplinkPush

/// Covers the Notification Content Extension helper: how a campaign's
/// carousel and countdown are read out of the payload, how the view pages and
/// counts, and — for every shape of malformed input — that the result is less
/// content rather than a broken view or a throw.
final class DyplinkNotificationContentTests: XCTestCase {

    private static let carouselKey = "dyplink_carousel"
    private static let timerKey = "dyplink_timer"

    override func setUp() {
        super.setUp()
        // The view starts downloading slide images the moment it is built.
        // Stubbing keeps the tests off the network rather than waiting out a
        // DNS failure per slide.
        let png = Self.pngData()
        StubURLProtocol.respond { _ in
            .success(statusCode: 200, headerFields: ["Content-Type": "image/png"], body: png)
        }
    }

    override func tearDown() {
        StubURLProtocol.stopIntercepting()
        super.tearDown()
    }

    // ── Parsing a carousel ─────────────────────────────────────────────

    func testValidCarouselIsParsed() throws {
        let slides = DyplinkNotificationContent.carouselSlides(in: [
            Self.carouselKey: Self.json([
                ["imageUrl": "https://cdn.test/1.png", "caption": "Day one",
                 "deepLinkUrl": "https://dyp.link/a"],
                ["imageUrl": "https://cdn.test/2.png"],
            ]),
        ])

        XCTAssertEqual(slides.count, 2)
        XCTAssertEqual(slides[0].imageUrl, URL(string: "https://cdn.test/1.png"))
        XCTAssertEqual(slides[0].caption, "Day one")
        XCTAssertEqual(slides[0].deepLinkUrl, "https://dyp.link/a")
        // An image alone is a valid slide.
        XCTAssertNil(slides[1].caption)
        XCTAssertNil(slides[1].deepLinkUrl)
    }

    /// One unusable frame costs a frame, not the carousel.
    func testUnusableSlidesAreDroppedIndividually() throws {
        let slides = DyplinkNotificationContent.carouselSlides(in: [
            Self.carouselKey: Self.json([
                ["imageUrl": "https://cdn.test/1.png"],
                ["caption": "no image at all"],
                ["imageUrl": "   "],
                ["imageUrl": 42],
                ["imageUrl": "https://cdn.test/2.png", "caption": "  "],
            ] as [Any]),
        ])

        XCTAssertEqual(slides.count, 2)
        // A whitespace-only caption is absent, not present-and-blank.
        XCTAssertNil(slides[1].caption)
    }

    /// A payload claiming more slides than the backend will ever compose has
    /// been corrupted; each extra slide is a decoded image in an extension
    /// with very little memory.
    func testCarouselIsCappedAtTheBackendMaximum() throws {
        let many = (0..<25).map { ["imageUrl": "https://cdn.test/\($0).png"] }
        let slides = DyplinkNotificationContent.carouselSlides(in: [
            Self.carouselKey: Self.json(many),
        ])

        XCTAssertEqual(slides.count, DyplinkNotificationContent.maxSlides)
    }

    // ── Parsing a timer ────────────────────────────────────────────────

    func testValidTimerIsParsed() throws {
        let timer = try XCTUnwrap(DyplinkNotificationContent.timer(in: [
            Self.timerKey: Self.json([
                "endsAt": "2030-01-01T00:00:00Z",
                "expiredTitle": "Sale over",
                "expiredBody": "Back next month",
            ]),
        ]))

        XCTAssertEqual(timer.endsAt.timeIntervalSince1970, 1_893_456_000, accuracy: 1)
        XCTAssertEqual(timer.expiredTitle, "Sale over")
        XCTAssertEqual(timer.expiredBody, "Back next month")
        XCTAssertFalse(timer.hasExpired)
    }

    /// `JSON.stringify` on a JavaScript `Date` emits milliseconds and a
    /// hand-entered timestamp usually does not; neither format parses the
    /// other, so both have to work.
    func testTimerAcceptsAnEndTimeWithOrWithoutFractionalSeconds() throws {
        for endsAt in ["2030-01-01T00:00:00Z", "2030-01-01T00:00:00.000Z"] {
            let timer = try XCTUnwrap(DyplinkNotificationContent.timer(in: [
                Self.timerKey: Self.json(["endsAt": endsAt]),
            ]), endsAt)

            XCTAssertEqual(timer.endsAt.timeIntervalSince1970, 1_893_456_000, accuracy: 1, endsAt)
            XCTAssertNil(timer.expiredTitle)
        }
    }

    // ── Degrading rather than throwing ─────────────────────────────────

    /// Both keys cross a process boundary as strings and may hold anything.
    func testMalformedRichContentYieldsNoView() throws {
        let payloads: [(name: String, userInfo: [AnyHashable: Any])] = [
            ("no rich content at all", ["dyplink_campaign_id": "camp-1"]),
            ("carousel is not JSON", [Self.carouselKey: "{not json"]),
            ("carousel is an object", [Self.carouselKey: Self.json(["imageUrl": "https://cdn.test/1.png"])]),
            ("carousel is empty", [Self.carouselKey: "[]"]),
            ("carousel is not a string", [Self.carouselKey: 42]),
            ("no slide has an image", [Self.carouselKey: Self.json([["caption": "a"], ["caption": "b"]])]),
            ("timer is not JSON", [Self.timerKey: "}{"]),
            ("timer has no end time", [Self.timerKey: Self.json(["expiredTitle": "Over"])]),
            ("timer end time will not parse", [Self.timerKey: Self.json(["endsAt": "next tuesday"])]),
            ("timer end time is not a string", [Self.timerKey: Self.json(["endsAt": 1_893_456_000])]),
        ]

        for payload in payloads {
            XCTAssertNil(
                DyplinkNotificationContent.makeView(for: makeRequest(userInfo: payload.userInfo)),
                payload.name
            )
        }
    }

    /// The two keys are independent on the wire, so they degrade
    /// independently: a broken countdown must not cost the carousel.
    func testCarouselSurvivesAnUnparseableTimer() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.carouselKey: Self.json([
                ["imageUrl": "https://cdn.test/1.png"],
                ["imageUrl": "https://cdn.test/2.png"],
            ]),
            Self.timerKey: Self.json(["endsAt": "not-a-date"]),
        ])))

        XCTAssertEqual(view.slides.count, 2)
        XCTAssertNil(view.timer)
        XCTAssertNil(view.countdownText)
    }

    /// A payload that was decoded and re-encoded somewhere along the way
    /// arrives structured rather than as a string.
    func testAlreadyDecodedRichContentIsAccepted() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.carouselKey: [
                ["imageUrl": "https://cdn.test/1.png", "caption": "One"],
                ["imageUrl": "https://cdn.test/2.png"],
            ],
        ])))

        XCTAssertEqual(view.slides.count, 2)
        XCTAssertEqual(view.slides.first?.caption, "One")
    }

    // ── The countdown ──────────────────────────────────────────────────

    func testCountdownIsFormattedAsAClock() {
        let format = DyplinkNotificationContentView.formattedCountdown(remaining:)

        XCTAssertEqual(format(0), "00:00:00")
        XCTAssertEqual(format(59), "00:00:59")
        XCTAssertEqual(format(3661), "01:01:01")
        // Spelled out, because "51:14:07" reads as an error rather than as
        // two days.
        XCTAssertEqual(format(2 * 86_400 + 3661), "2d 01:01:01")
        // A clock that has run past zero shows zero, never a negative.
        XCTAssertEqual(format(-500), "00:00:00")
    }

    func testRunningCountdownShowsTheRemainingTime() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.timerKey: Self.json(["endsAt": Self.iso8601(fromNow: 3600)]),
        ])))

        // Painted at construction rather than on the first tick, so the view
        // never appears with a blank gap where the clock will be. The exact
        // digits are a second away from racing the clock; `formattedCountdown`
        // is what pins those down.
        let text = try XCTUnwrap(view.countdownText)
        XCTAssertNotNil(text.range(of: "^[0-9]{2}:[0-9]{2}:[0-9]{2}$", options: .regularExpression), text)
        XCTAssertNil(view.expiredBodyText)
    }

    func testAlreadyExpiredTimerShowsTheExpiredCopy() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.timerKey: Self.json([
                "endsAt": Self.iso8601(fromNow: -60),
                "expiredTitle": "Sale over",
                "expiredBody": "Back next month",
            ]),
        ])))

        XCTAssertEqual(view.countdownText, "Sale over")
        XCTAssertEqual(view.expiredBodyText, "Back next month")
    }

    /// Absent expired copy falls back to the campaign's own title and body,
    /// which the notification is already showing above this view — so there is
    /// nothing left to draw, and a frozen zero would only be worse.
    func testExpiredTimerWithoutCopyDrawsNothing() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.timerKey: Self.json(["endsAt": Self.iso8601(fromNow: -60)]),
        ])))

        XCTAssertNil(view.countdownText)
        XCTAssertNil(view.expiredBodyText)
    }

    /// A timer left ticking after the notification is gone is a battery
    /// complaint, and the window is the signal that reliably arrives — a
    /// content extension's view controller often is not told it disappeared.
    func testCountdownStopsWhenTheViewLeavesItsWindow() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.timerKey: Self.json(["endsAt": Self.iso8601(fromNow: 3600)]),
        ])))
        XCTAssertFalse(view.isCountdownRunning, "nothing should tick before the view is installed")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        window.addSubview(view)
        XCTAssertTrue(view.isCountdownRunning)

        view.removeFromSuperview()
        XCTAssertFalse(view.isCountdownRunning)
    }

    /// An expired campaign has nothing left to count, so installing it must
    /// not schedule a timer whose only job is to invalidate itself.
    func testExpiredTimerNeverSchedulesATick() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.timerKey: Self.json(["endsAt": Self.iso8601(fromNow: -60), "expiredTitle": "Over"]),
        ])))

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        window.addSubview(view)

        XCTAssertFalse(view.isCountdownRunning)
        XCTAssertEqual(view.countdownText, "Over")
    }

    // ── Paging ─────────────────────────────────────────────────────────

    func testSlideNavigationStaysInRange() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.carouselKey: Self.json([
                ["imageUrl": "https://cdn.test/1.png", "deepLinkUrl": "https://dyp.link/a"],
                ["imageUrl": "https://cdn.test/2.png", "deepLinkUrl": "https://dyp.link/b"],
                ["imageUrl": "https://cdn.test/3.png"],
            ]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        view.layoutIfNeeded()

        XCTAssertEqual(view.currentSlideIndex, 0)
        XCTAssertEqual(view.currentSlide?.deepLinkUrl, "https://dyp.link/a")

        view.showNextSlide()
        XCTAssertEqual(view.currentSlideIndex, 1)
        XCTAssertEqual(view.currentSlide?.deepLinkUrl, "https://dyp.link/b")

        // Past the last slide wraps rather than stopping dead.
        view.showNextSlide()
        view.showNextSlide()
        XCTAssertEqual(view.currentSlideIndex, 0)

        view.showPreviousSlide()
        XCTAssertEqual(view.currentSlideIndex, 2)
        // A slide with no destination of its own falls back to the campaign's.
        XCTAssertNil(view.currentSlide?.deepLinkUrl)

        // Out of range is ignored, never a trap: an extension must not crash
        // over a caller working from a stale count.
        for index in [-1, 3, Int.max] {
            view.showSlide(at: index)
            XCTAssertEqual(view.currentSlideIndex, 2, "\(index)")
        }

        view.showSlide(at: 1)
        XCTAssertEqual(view.currentSlideIndex, 1)
    }

    /// A countdown-only campaign has no slide to attribute a tap to.
    func testCountdownOnlyCampaignHasNoCurrentSlide() throws {
        let view = try XCTUnwrap(DyplinkNotificationContent.makeView(for: makeRequest(userInfo: [
            Self.timerKey: Self.json(["endsAt": Self.iso8601(fromNow: 600)]),
        ])))

        XCTAssertTrue(view.slides.isEmpty)
        XCTAssertNil(view.currentSlide)
        view.showNextSlide()
        XCTAssertEqual(view.currentSlideIndex, 0)
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private func makeRequest(userInfo: [AnyHashable: Any]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Sale"
        content.body = "50% off everything"
        content.userInfo = userInfo
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    /// The wire format: both rich-content keys travel as JSON strings,
    /// because an APNs data key is a string.
    private static func json(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func iso8601(fromNow offset: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(offset))
    }

    private static func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData()!
    }
}
