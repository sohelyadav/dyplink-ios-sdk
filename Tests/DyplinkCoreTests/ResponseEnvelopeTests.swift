import XCTest
@testable import DyplinkCore

/// The API wraps every response in `{ "data": … }`, and for a long time the
/// SDK read fields straight off the root. Nothing errored: a deferred match
/// read as "not matched" and an identify result came back empty, which is
/// indistinguishable from the honest answer. These cover the unwrap that
/// closed that, and the fallback that keeps un-enveloped bodies working.
final class ResponseEnvelopeTests: XCTestCase {

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    func testStepsInsideTheDataEnvelope() throws {
        let body = data(#"{"data":{"matched":true,"shortCode":"abc123"}}"#)

        let json = try JSONUtils.decodeEnvelope(body)

        XCTAssertEqual(json["matched"] as? Bool, true)
        XCTAssertEqual(json["shortCode"] as? String, "abc123")
        // The envelope itself must not survive, or a caller reading
        // `data` would find the payload nested one level deeper.
        XCTAssertNil(json["data"])
    }

    func testFallsBackToTheRootWhenThereIsNoEnvelope() throws {
        // The deferred matcher caches its own result in this shape, and
        // parses it back with the same helpers.
        let body = data(#"{"matched":true,"linkId":"link-1"}"#)

        let json = try JSONUtils.decodeEnvelope(body)

        XCTAssertEqual(json["matched"] as? Bool, true)
        XCTAssertEqual(json["linkId"] as? String, "link-1")
    }

    func testFallsBackToTheRootWhenDataIsNotAnObject() throws {
        // `data` holding an array is a real response shape — a list
        // endpoint — and the payload is then the root, not the array.
        let body = data(#"{"data":[1,2,3],"meta":{"total":3}}"#)

        let json = try JSONUtils.decodeEnvelope(body)

        XCTAssertNotNil(json["data"])
        XCTAssertNotNil(json["meta"])
    }

    func testEmptyBodyDecodesToAnEmptyObject() throws {
        XCTAssertTrue(try JSONUtils.decodeEnvelope(Data()).isEmpty)
    }

    func testNullDataFallsBackToTheRoot() throws {
        let body = data(#"{"data":null,"matched":false}"#)

        let json = try JSONUtils.decodeEnvelope(body)

        XCTAssertEqual(json["matched"] as? Bool, false)
    }
}
