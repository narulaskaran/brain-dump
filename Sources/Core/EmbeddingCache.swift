import Foundation

/// Persistent cache of embedding vectors keyed by absolute file path.
public struct EmbeddingCache: Codable, Sendable {

    /// A single cached embedding entry.
    public struct Entry: Codable, Sendable {
        /// Last modification date of the source file at the time of embedding.
        public var mtime: Date
        /// The embedding vector.
        public var vector: [Double]

        public init(mtime: Date, vector: [Double]) {
            self.mtime = mtime
            self.vector = vector
        }
    }

    /// Map from absolute file path to its cached entry.
    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    // MARK: - Disk persistence

    private static func cacheURL(vaultPath: URL) -> URL {
        vaultPath.appendingPathComponent(".embeddings.json")
    }

    /// Loads the cache from `vaultPath/.embeddings.json`.
    /// Returns an empty cache if the file does not exist or cannot be decoded.
    public static func load(vaultPath: URL) -> EmbeddingCache {
        let url = EmbeddingCache.cacheURL(vaultPath: vaultPath)
        guard let data = try? Data(contentsOf: url) else { return EmbeddingCache() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(EmbeddingCache.self, from: data)) ?? EmbeddingCache()
    }

    /// Saves the cache to `vaultPath/.embeddings.json`.
    public mutating func save(vaultPath: URL) throws {
        let url = EmbeddingCache.cacheURL(vaultPath: vaultPath)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
