import Foundation

/// Errors thrown by LLM provider implementations.
public enum LLMError: Error, Sendable {
    /// The server returned a non-2xx HTTP status code.
    case httpError(statusCode: Int, body: String)
    /// The response body could not be decoded.
    case decodingError(String)
    /// A network-level error occurred.
    case networkError(any Error & Sendable)
    /// The response contained no usable content.
    case noContent
}
