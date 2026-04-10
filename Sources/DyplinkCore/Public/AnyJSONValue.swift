import Foundation

/// Type-erased JSON value that the SDK uses for heterogeneous user
/// properties, traits, and metadata.
///
/// This is the Swift analogue of Kotlin's `Any` values inside
/// `Map<String, Any>`. Only JSON-compatible primitives are accepted:
/// `String`, `Int`, `Double`, `Bool`, `[AnyJSONValue]`,
/// `[String: AnyJSONValue]`, or `nil`. Anything else is converted to
/// its `String(describing:)` representation as a last resort so the
/// wrapper never refuses to store a value passed through from user code.
public struct AnyJSONValue: Sendable, Equatable {

    public let value: Value

    public enum Value: Sendable, Equatable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyJSONValue])
        case object([String: AnyJSONValue])
    }

    /// Creates a wrapper from any bridgeable value. Objective-C bridged
    /// numeric types (`NSNumber`) are routed to the appropriate case.
    public init(_ raw: Any?) {
        switch raw {
        case .none:
            self.value = .null
        case let b as Bool:
            self.value = .bool(b)
        case let i as Int:
            self.value = .int(i)
        case let i as Int64:
            self.value = .int(Int(i))
        case let u as UInt:
            self.value = .int(Int(u))
        case let d as Double:
            self.value = .double(d)
        case let f as Float:
            self.value = .double(Double(f))
        case let s as String:
            self.value = .string(s)
        case let a as [Any?]:
            self.value = .array(a.map { AnyJSONValue($0) })
        case let m as [String: Any?]:
            self.value = .object(m.mapValues { AnyJSONValue($0) })
        case let m as [String: Any]:
            self.value = .object(m.mapValues { AnyJSONValue($0 as Any?) })
        case let other?:
            self.value = .string(String(describing: other))
        }
    }

    public init(_ value: Value) {
        self.value = value
    }

    /// Converts back to a Foundation-compatible JSON value suitable for
    /// `JSONSerialization.data(withJSONObject:)`.
    public func asFoundationJSON() -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.asFoundationJSON() }
        case .object(let m): return m.mapValues { $0.asFoundationJSON() }
        }
    }
}

extension Dictionary where Key == String, Value == AnyJSONValue {
    /// Convert a `[String: AnyJSONValue]` map into a plain
    /// `[String: Any]` dictionary suitable for `JSONSerialization`.
    public func asFoundationJSON() -> [String: Any] {
        mapValues { $0.asFoundationJSON() }
    }
}
