import XCTest
import DyplinkCore
@testable import DyplinkBanners

/// Covers the requests the banner module sends.
///
/// Both of its endpoints are behind `ApiKeyGuard`, and neither request
/// carried `X-API-Key`: the serve call answered 401, so `BannerCarouselView`
/// rendered nothing on every real deployment, and the click call answered
/// 401 too, so no banner click was ever recorded. Ten green tests covered
/// this module and not one of them looked at a request — which is exactly
/// how a module that could never have worked stayed green.
final class BannerApiClientTests: XCTestCase {

    private let apiKey = "dyplink_test_key"
    private let categoryId = "0ea3f1c0-0000-4000-8000-000000000001"

    override func setUp() {
        super.setUp()
        DyplinkConfigBridge.baseUrl = "https://api.test"
        DyplinkConfigBridge.apiKey = apiKey
        DyplinkConfigBridge.projectId = "project-1"
    }

    override func tearDown() {
        StubURLProtocol.stopIntercepting()
        super.tearDown()
    }

    /// The request the client sends for `path`, or nil if it sent none.
    private func capturedRequest(
        for path: String,
        _ work: @escaping () async -> Void
    ) async -> URLRequest? {
        let captured = UncheckedBox<URLRequest?>(nil)
        StubURLProtocol.startIntercepting { request in
            guard request.url?.path == path else { return }
            captured.value = request
        }
        await work()
        return captured.value
    }

    // ── The header ─────────────────────────────────────────────────────

    func testServingBannersCarriesTheApiKey() async throws {
        let request = await capturedRequest(for: "/api/in-app-banners/serve/\(categoryId)") {
            _ = try? await BannerApiClient().fetchBanners(categoryId: self.categoryId)
        }

        let sent = try XCTUnwrap(request, "no serve request was sent")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-API-Key"), apiKey)
    }

    func testTrackingAClickCarriesTheApiKey() async throws {
        let bannerId = "0ea3f1c0-0000-4000-8000-000000000002"
        let request = await capturedRequest(for: "/api/in-app-banners/\(bannerId)/click") {
            await BannerApiClient().trackClick(bannerId: bannerId)
        }

        let sent = try XCTUnwrap(request, "no click request was sent")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-API-Key"), apiKey)
        XCTAssertEqual(sent.httpMethod, "POST")
    }

    // ── The route ──────────────────────────────────────────────────────

    /// `GET /api/in-app-banners/serve/:categoryId`, the route the guard is
    /// on. The web SDK was corrected to this one.
    func testBannersAreServedFromTheScopedServeRoute() async throws {
        let request = await capturedRequest(for: "/api/in-app-banners/serve/\(categoryId)") {
            _ = try? await BannerApiClient().fetchBanners(categoryId: self.categoryId)
        }

        let sent = try XCTUnwrap(request)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.test/api/in-app-banners/serve/\(categoryId)")
        XCTAssertEqual(sent.httpMethod, "GET")
    }

    // ── What a refusal does ────────────────────────────────────────────

    /// The 401 this used to answer with, so the error carries the status and
    /// the body rather than the carousel silently rendering nothing.
    func testARefusedServeSurfacesTheStatusAndTheBody() async {
        StubURLProtocol.respond { _ in
            .success(
                statusCode: 401,
                headerFields: ["Content-Type": "application/json"],
                body: Data(#"{"statusCode":401,"message":"Invalid API key"}"#.utf8)
            )
        }

        do {
            _ = try await BannerApiClient().fetchBanners(categoryId: categoryId)
            XCTFail("expected a 401 to be surfaced")
        } catch let error as DyplinkError {
            guard case .apiError(_, let statusCode, let body) = error else {
                return XCTFail("expected an apiError, got \(error)")
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(body?.contains("Invalid API key"), true)
        } catch {
            XCTFail("expected a DyplinkError, got \(error)")
        }
    }
}
