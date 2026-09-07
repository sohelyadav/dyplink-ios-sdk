import XCTest
import UIKit
import UserNotifications
@testable import DyplinkPush

/// Covers the Notification Service Extension helper: when a campaign's image
/// is attached, how its file type is derived, and — on every path, including
/// each failure — that the notification is still delivered, exactly once.
final class DyplinkNotificationServiceTests: XCTestCase {

    private static let imageUrlKey = "dyplink_image_url"

    override func tearDown() {
        StubURLProtocol.stopIntercepting()
        super.tearDown()
    }

    // ── No image ───────────────────────────────────────────────────────

    func testPayloadWithoutAnImageDeliversTheOriginalContentImmediately() throws {
        let request = makeRequest(userInfo: ["dyplink_campaign_id": "camp-1"])
        let original = request.content
        let deliveries = Deliveries()

        DyplinkNotificationService.populate(request) { deliveries.record($0) }

        // Delivered before `populate` returned, not merely delivered: an
        // extension that holds back a notification it has nothing to add to
        // is worse than no extension at all.
        XCTAssertEqual(deliveries.contents.count, 1)
        XCTAssertTrue(deliveries.contents.first === original)
        XCTAssertEqual(deliveries.contents.first?.attachments.count, 0)
    }

    /// `userInfo` arrives from the OS untyped and can hold anything.
    func testImageUrlValuesThatAreNotUsableStringsDeliverTheOriginal() throws {
        for value in [42, "", "   "] as [Any] {
            let request = makeRequest(userInfo: [Self.imageUrlKey: value])
            let deliveries = Deliveries()

            DyplinkNotificationService.populate(request) { deliveries.record($0) }

            XCTAssertEqual(deliveries.contents.count, 1, "\(value)")
            XCTAssertEqual(deliveries.contents.first?.attachments.count, 0, "\(value)")
        }
    }

    // ── Attaching the image ────────────────────────────────────────────

    func testDownloadedImageIsAttached() throws {
        stub(.success(statusCode: 200,
                      headerFields: ["Content-Type": "image/png"],
                      body: Self.pngData()))

        let content = try deliver(makeRequest(userInfo: [
            "dyplink_campaign_id": "camp-2",
            Self.imageUrlKey: "https://cdn.test/campaign.png",
        ]))

        XCTAssertEqual(content.attachments.count, 1)
        // The rest of the notification has to survive the copy.
        XCTAssertEqual(content.title, "Sale")
        XCTAssertEqual(content.body, "50% off everything")
        XCTAssertEqual(content.userInfo["dyplink_campaign_id"] as? String, "camp-2")
    }

    /// A CDN URL often ends in a hash with no extension at all, so the
    /// response's own `Content-Type` has to be enough to type the file.
    func testFileTypeIsDerivedFromTheContentTypeWhenTheUrlHasNone() throws {
        stub(.success(statusCode: 200,
                      headerFields: ["Content-Type": "image/jpeg"],
                      body: Self.jpegData()))

        let content = try deliver(makeRequest(userInfo: [
            Self.imageUrlKey: "https://cdn.test/assets/8f2a1c9e",
        ]))

        XCTAssertEqual(content.attachments.count, 1)
    }

    /// And with no `Content-Type` to go on, the URL is all there is.
    func testFileTypeFallsBackToTheUrlExtension() throws {
        stub(.success(statusCode: 200, headerFields: [:], body: Self.pngData()))

        let content = try deliver(makeRequest(userInfo: [
            Self.imageUrlKey: "https://cdn.test/campaign.png",
        ]))

        XCTAssertEqual(content.attachments.count, 1)
    }

    // ── Never failing the notification ─────────────────────────────────

    func testDownloadFailureStillDeliversTheOriginal() throws {
        stub(.failure(.cannotConnectToHost))

        let content = try deliver(makeRequest(userInfo: [
            Self.imageUrlKey: "https://cdn.test/campaign.png",
        ]))

        XCTAssertEqual(content.attachments.count, 0)
        XCTAssertEqual(content.title, "Sale")
    }

    /// A URL that 404s to an HTML error page: the extension must not be
    /// trusted over the `Content-Type`, and nothing may be attached.
    func testNonImageResponseStillDeliversTheOriginal() throws {
        stub(.success(statusCode: 200,
                      headerFields: ["Content-Type": "text/html"],
                      body: Data("<html>not found</html>".utf8)))

        let content = try deliver(makeRequest(userInfo: [
            Self.imageUrlKey: "https://cdn.test/campaign.png",
        ]))

        XCTAssertEqual(content.attachments.count, 0)
        XCTAssertEqual(content.title, "Sale")
    }

    func testErrorStatusStillDeliversTheOriginal() throws {
        stub(.success(statusCode: 500,
                      headerFields: ["Content-Type": "image/png"],
                      body: Self.pngData()))

        let content = try deliver(makeRequest(userInfo: [
            Self.imageUrlKey: "https://cdn.test/campaign.png",
        ]))

        XCTAssertEqual(content.attachments.count, 0)
    }

    // ── Exactly once ───────────────────────────────────────────────────

    /// A handler called twice traps in a real extension, and one never
    /// called leaves the notification hanging until the system's deadline.
    func testHandlerIsCalledExactlyOnceOnEveryPath() {
        let scenarios: [(name: String, response: StubURLProtocol.StubResponse?, userInfo: [AnyHashable: Any])] = [
            ("no image", nil, ["dyplink_campaign_id": "camp-3"]),
            ("unusable image url", nil, [Self.imageUrlKey: 42]),
            ("image downloaded",
             .success(statusCode: 200, headerFields: ["Content-Type": "image/png"], body: Self.pngData()),
             [Self.imageUrlKey: "https://cdn.test/campaign.png"]),
            ("download failed",
             .failure(.timedOut),
             [Self.imageUrlKey: "https://cdn.test/campaign.png"]),
            ("not an image",
             .success(statusCode: 200, headerFields: ["Content-Type": "text/html"], body: Data("<html>".utf8)),
             [Self.imageUrlKey: "https://cdn.test/campaign.png"]),
        ]

        for scenario in scenarios {
            if let response = scenario.response { stub(response) }

            let deliveries = Deliveries()
            let called = expectation(description: scenario.name)
            let noSecondCall = expectation(description: "only once: \(scenario.name)")
            noSecondCall.isInverted = true

            DyplinkNotificationService.populate(makeRequest(userInfo: scenario.userInfo)) { content in
                deliveries.record(content)
                if deliveries.contents.count == 1 { called.fulfill() } else { noSecondCall.fulfill() }
            }

            wait(for: [called], timeout: 5)
            wait(for: [noSecondCall], timeout: 0.3)
            XCTAssertEqual(deliveries.contents.count, 1, scenario.name)
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private func makeRequest(userInfo: [AnyHashable: Any]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Sale"
        content.body = "50% off everything"
        content.userInfo = userInfo
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    private func stub(_ response: StubURLProtocol.StubResponse) {
        StubURLProtocol.respond { _ in response }
    }

    /// Runs `populate` and returns the one content it delivered.
    private func deliver(
        _ request: UNNotificationRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UNNotificationContent {
        let deliveries = Deliveries()
        let called = expectation(description: "content handler called")

        DyplinkNotificationService.populate(request) { content in
            deliveries.record(content)
            called.fulfill()
        }

        wait(for: [called], timeout: 5)
        XCTAssertEqual(deliveries.contents.count, 1, file: file, line: line)
        return try XCTUnwrap(deliveries.contents.first, file: file, line: line)
    }

    /// `UNNotificationAttachment` validates the bytes it is handed, not just
    /// the file name, so the stub has to serve a real image.
    private static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private static func pngData() -> Data { image().pngData()! }

    private static func jpegData() -> Data { image().jpegData(compressionQuality: 0.8)! }
}

/// Collects the contents handed to the handler, which the SDK may invoke
/// from the URL loading system's thread.
private final class Deliveries: @unchecked Sendable {
    private let lock = NSLock()
    private var _contents: [UNNotificationContent] = []

    var contents: [UNNotificationContent] {
        lock.lock(); defer { lock.unlock() }
        return _contents
    }

    func record(_ content: UNNotificationContent) {
        lock.lock(); defer { lock.unlock() }
        _contents.append(content)
    }
}
