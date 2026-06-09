import Foundation

/// A `Sendable` representation of a JSON value, used in place of `[String: Any]`
/// for tool schemas and tool call inputs.
public indirect enum JSONValue: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Conversion helpers

extension JSONValue {
    /// Convert to a Foundation-compatible `Any` value (useful for JSONSerialization).
    public func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        }
    }

    /// Build a `JSONValue` from a Foundation-compatible `Any` value.
    public static func from(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull: return .null
        case let b as Bool: return .bool(b)
        case let n as Double: return .number(n)
        case let n as Int: return .number(Double(n))
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map { .from($0) })
        case let o as [String: Any]: return .object(o.mapValues { .from($0) })
        default: return .null
        }
    }
}
