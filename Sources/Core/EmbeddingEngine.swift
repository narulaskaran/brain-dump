import Foundation
import NaturalLanguage

/// Computes sentence embeddings and cosine similarity using NaturalLanguage.
public actor EmbeddingEngine {

    private let embedding: NLEmbedding?

    public init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Returns an embedding vector for the given text.
    /// Uses the first 500 characters to keep costs low.
    /// Falls back to an empty vector if NLEmbedding is unavailable.
    public func embed(_ text: String) -> [Double] {
        guard let embedding else { return [] }
        let truncated = String(text.prefix(500))
        guard !truncated.isEmpty else { return [] }
        guard let vector = embedding.vector(for: truncated) else { return [] }
        return vector.map { Double($0) }
    }

    /// Cosine similarity between two vectors. Returns 0 if either is empty or
    /// if the denominator is zero.
    public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty, a.count == b.count else { return 0 }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
