import XCTest
@testable import DyplinkCore

final class AnyJSONValueTests: XCTestCase {

    func testStringValue() {
        let v = AnyJSONValue("hello")
        XCTAssertEqual(v.value, .string("hello"))
    }

    func testIntValue() {
        let v = AnyJSONValue(42)
        XCTAssertEqual(v.value, .int(42))
    }

    func testDoubleValue() {
        let v = AnyJSONValue(3.14)
        XCTAssertEqual(v.value, .double(3.14))
    }

    func testBoolValue() {
        let v = AnyJSONValue(true)
        XCTAssertEqual(v.value, .bool(true))
    }

    func testNilValue() {
        let v = AnyJSONValue(nil as Any?)
        XCTAssertEqual(v.value, .null)
    }

    func testArrayValue() {
        let v = AnyJSONValue(["a", "b"] as [Any?])
        if case .array(let arr) = v.value {
            XCTAssertEqual(arr.count, 2)
            XCTAssertEqual(arr[0].value, .string("a"))
        } else {
            XCTFail("Expected array")
        }
    }

    func testObjectValue() {
        let v = AnyJSONValue(["key": "val"] as [String: Any?])
        if case .object(let obj) = v.value {
            XCTAssertEqual(obj["key"]?.value, .string("val"))
        } else {
            XCTFail("Expected object")
        }
    }

    func testAsFoundationJSON_roundTrip() throws {
        let original: [String: Any] = [
            "name": "test",
            "count": 42,
            "active": true,
            "tags": ["a", "b"],
        ]
        let wrapped = original.mapValues { AnyJSONValue($0) }
        let foundation = wrapped.asFoundationJSON()

        // Verify JSON serialization works.
        let data = try JSONSerialization.data(withJSONObject: foundation)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(decoded?["name"] as? String, "test")
        XCTAssertEqual(decoded?["count"] as? Int, 42)
        XCTAssertEqual(decoded?["active"] as? Bool, true)
    }
}
