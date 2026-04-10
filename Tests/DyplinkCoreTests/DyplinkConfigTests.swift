import XCTest
@testable import DyplinkCore

final class DyplinkConfigTests: XCTestCase {

    func testBuildWithRequiredFieldsOnly() throws {
        let config = try DyplinkConfig.Builder(
            baseUrl: "https://api.dyplink.com",
            apiKey: "k",
            projectId: "p"
        ).build()

        XCTAssertEqual(config.baseUrl, "https://api.dyplink.com")
        XCTAssertEqual(config.apiKey, "k")
        XCTAssertEqual(config.projectId, "p")
        XCTAssertEqual(config.logLevel, .none)
        XCTAssertEqual(config.flushIntervalSeconds, 30)
        XCTAssertEqual(config.maxQueueSize, 1000)
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.sessionTimeoutSeconds, 300)
        XCTAssertTrue(config.enableAutoSessionTracking)
        XCTAssertTrue(config.enableAutoDeviceInfo)
        XCTAssertTrue(config.deepLinkHosts.isEmpty)
        XCTAssertNil(config.customScheme)
    }

    func testBuildWithAllOptionalFields() throws {
        let config = try DyplinkConfig.Builder(
            baseUrl: "https://api.dyplink.com",
            apiKey: "k",
            projectId: "p"
        )
        .logLevel(.debug)
        .flushInterval(60)
        .maxQueueSize(500)
        .maxRetries(5)
        .sessionTimeout(600)
        .enableAutoSessionTracking(false)
        .enableAutoDeviceInfo(false)
        .deepLinkHosts(["a.example.com", "b.example.com"])
        .customScheme("myapp")
        .build()

        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertEqual(config.flushIntervalSeconds, 60)
        XCTAssertEqual(config.maxQueueSize, 500)
        XCTAssertEqual(config.maxRetries, 5)
        XCTAssertEqual(config.sessionTimeoutSeconds, 600)
        XCTAssertFalse(config.enableAutoSessionTracking)
        XCTAssertFalse(config.enableAutoDeviceInfo)
        XCTAssertEqual(config.deepLinkHosts, ["a.example.com", "b.example.com"])
        XCTAssertEqual(config.customScheme, "myapp")
    }

    func testBuildRejectsBlankBaseUrl() {
        XCTAssertThrowsError(try DyplinkConfig.Builder(
            baseUrl: "",
            apiKey: "k",
            projectId: "p"
        ).build())
    }

    func testBuildRejectsBlankApiKey() {
        XCTAssertThrowsError(try DyplinkConfig.Builder(
            baseUrl: "https://api.dyplink.com",
            apiKey: "  ",
            projectId: "p"
        ).build())
    }

    func testBuildRejectsNonPositiveFlushInterval() {
        XCTAssertThrowsError(try DyplinkConfig.Builder(
            baseUrl: "https://api.dyplink.com",
            apiKey: "k",
            projectId: "p"
        ).flushInterval(0).build())
    }

    func testBuildRejectsNegativeMaxRetries() {
        XCTAssertThrowsError(try DyplinkConfig.Builder(
            baseUrl: "https://api.dyplink.com",
            apiKey: "k",
            projectId: "p"
        ).maxRetries(-1).build())
    }

    func testBaseUrlTrailingSlashTrimmed() throws {
        let config = try DyplinkConfig.Builder(
            baseUrl: "https://api.dyplink.com/",
            apiKey: "k",
            projectId: "p"
        ).build()
        XCTAssertEqual(config.baseUrl, "https://api.dyplink.com")
    }
}
