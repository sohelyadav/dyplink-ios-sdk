import Foundation

/// JSON helpers shared across the SDK. The Android equivalents live in
/// `com.dyplink.sdk.internal.util.JsonUtils`.
internal enum JSONUtils {

    /// Serialize a `[String: Any]` dictionary into a UTF-8 JSON string.
    /// Throws `DyplinkError.apiError` if serialization fails.
    static func encode(_ dict: [String: Any]) throws -> Data {
        do {
            // `.sortedKeys` makes request bodies deterministic for tests.
            return try JSONSerialization.data(
                withJSONObject: dict,
                options: [.sortedKeys]
            )
        } catch {
            throw DyplinkError.apiError(
                message: "Failed to encode JSON body: \(error.localizedDescription)",
                statusCode: 0
            )
        }
    }

    /// Decode a JSON `Data` blob into a top-level dictionary. Returns
    /// `[:]` when the blob is empty.
    static func decodeObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw DyplinkError.apiError(
                message: "Expected top-level JSON object, got \(type(of: obj))",
                statusCode: 0
            )
        }
        return dict
    }

    /// Convert a raw JSON value (as returned by `JSONSerialization`) to
    /// a `[String: AnyJSONValue]` map. Values that aren't objects are
    /// silently dropped.
    static func toAnyJSONMap(_ raw: Any?) -> [String: AnyJSONValue]? {
        guard let dict = raw as? [String: Any] else { return nil }
        return dict.mapValues { AnyJSONValue($0) }
    }
}
