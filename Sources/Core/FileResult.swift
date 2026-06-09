import Foundation

/// Represents a single search result from the vault index.
public struct FileResult: Sendable {
    /// Absolute path to the Markdown file.
    public let path: String
    /// Path relative to the vault root.
    public let relativePath: String
    /// First ATX H1 heading in the file, or the filename stem if none found.
    public let title: String
    /// First 500 characters of the file's content.
    public let snippet: String
    /// Cosine similarity score against the search query (higher is more similar).
    public let score: Double

    public init(
        path: String,
        relativePath: String,
        title: String,
        snippet: String,
        score: Double
    ) {
        self.path = path
        self.relativePath = relativePath
        self.title = title
        self.snippet = snippet
        self.score = score
    }
}
