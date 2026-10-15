import XCTest
@testable import DyplinkCore

/// Covers the body `POST /api/deferred/match` is sent — the one thing that
/// decides whether a deferred match can succeed at all.
///
/// The request carried a fingerprint and nothing else. The server tries
/// `cookieRef` first, and it names the link outright; the fingerprint path
/// is a correlation over a 48 hour window. With no `cookieRef` ever sent, a
/// device the server could have identified exactly was matched by
/// correlation or not at all — and a failed match is a plain
/// `matched: false`, indistinguishable from a device that never clicked.
final class DeferredMatchRequestTests: XCTestCase {

    private let deviceInfo: [String: Any] = [
        "os": "iOS",
        "osVersion": "18.2",
        "model": "iPhone17,1",
        "screenWidth": 393,
        "screenHeight": 852,
        // `DeviceInfoCollector` collects more than the match uses; the extra
        // must not reach the body, where `forbidNonWhitelisted` makes one
        // unexpected key a 400 for the whole request.
        "appVersion": "2.1.0",
        "locale": "en_GB",
    ]

    private func body(cookieRef: String? = nil) -> [String: Any] {
        DeferredDeepLinkMatcher.requestBody(deviceInfo: deviceInfo, cookieRef: cookieRef)
    }

    // ── cookieRef ──────────────────────────────────────────────────────

    func testTheCookieRefIsSentWhenThereIsOne() {
        XCTAssertEqual(body(cookieRef: "abc123")["cookieRef"] as? String, "abc123")
    }

    func testTheCookieRefIsOmittedRatherThanSentAsNull() {
        let sent = body(cookieRef: nil)

        XCTAssertFalse(sent.keys.contains("cookieRef"))
        XCTAssertFalse(sent["cookieRef"] is NSNull)
    }

    /// `@IsString()` accepts `"   "`, and the server then looks up a link
    /// with that short code and finds none — a round trip for nothing.
    func testABlankCookieRefIsTreatedAsAbsent() {
        XCTAssertFalse(body(cookieRef: "   ").keys.contains("cookieRef"))
        XCTAssertFalse(body(cookieRef: "").keys.contains("cookieRef"))
    }

    func testTheCookieRefIsTrimmed() {
        XCTAssertEqual(body(cookieRef: "  abc123\n")["cookieRef"] as? String, "abc123")
    }

    // ── The fingerprint ────────────────────────────────────────────────

    func testTheFingerprintCarriesWhatTheServerMatchesOn() throws {
        let fingerprint = try XCTUnwrap(body()["fingerprint"] as? [String: Any])

        XCTAssertEqual(fingerprint["os"] as? String, "iOS")
        XCTAssertEqual(fingerprint["osVersion"] as? String, "18.2")
        XCTAssertEqual(fingerprint["model"] as? String, "iPhone17,1")
        XCTAssertEqual(fingerprint["screenWidth"] as? Int, 393)
        XCTAssertEqual(fingerprint["screenHeight"] as? Int, 852)
    }

    /// The server reads the IP off the request. A client that sent its own
    /// would be naming an address it was never at — a click it could claim
    /// without having made it — so `FingerprintDto` does not accept one, and
    /// a body carrying it is a 400 for the whole request.
    func testTheIpIsNeverSent() throws {
        let fingerprint = try XCTUnwrap(body(cookieRef: "abc123")["fingerprint"] as? [String: Any])

        XCTAssertFalse(fingerprint.keys.contains("ip"))
    }

    /// `DeferredMatchDto` takes `fingerprint` and `cookieRef` and nothing
    /// else.
    func testNothingElseIsSent() {
        XCTAssertEqual(Set(body(cookieRef: "abc123").keys), ["fingerprint", "cookieRef"])
        XCTAssertEqual(Set(body().keys), ["fingerprint"])
    }

    /// A device that collected nothing sends no fingerprint rather than an
    /// empty one: `os` is required on the DTO.
    func testADeviceWithNoInfoSendsNoFingerprint() {
        let sent = DeferredDeepLinkMatcher.requestBody(
            deviceInfo: ["os": "", "model": ""],
            cookieRef: nil
        )

        XCTAssertTrue(sent.isEmpty)
    }

    /// The body is encodable as it stands — `JSONUtils.encode` throws on
    /// anything `JSONSerialization` will not take, and the matcher's one
    /// `catch` turns that into the same silent `matched: false`.
    func testTheBodyIsEncodable() throws {
        XCTAssertNoThrow(try JSONUtils.encode(body(cookieRef: "abc123")))
        let data = try JSONUtils.encode(body(cookieRef: "abc123"))
        let decoded = try JSONUtils.decodeObject(data)
        XCTAssertEqual(decoded["cookieRef"] as? String, "abc123")
    }
}
