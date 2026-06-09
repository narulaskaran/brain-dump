import Foundation

/// Tracks the state of the last grooming pass.
public struct GroomingState: Codable, Sendable {
    /// Whether the user has reviewed the grooming output.
    public var reviewed: Bool
    /// When this grooming pass was generated.
    public var generatedAt: Date
    /// Number of findings written.
    public var count: Int

    public init(reviewed: Bool = false, generatedAt: Date = Date(), count: Int = 0) {
        self.reviewed = reviewed
        self.generatedAt = generatedAt
        self.count = count
    }

    // MARK: - Persistence

    private static func stateURL(vaultPath: URL) -> URL {
        vaultPath.appendingPathComponent(".grooming-state.json")
    }

    /// Loads the grooming state from `vaultPath/.grooming-state.json`.
    /// Returns nil if the file does not exist or cannot be decoded.
    public static func load(vaultPath: URL) -> GroomingState? {
        let url = stateURL(vaultPath: vaultPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GroomingState.self, from: data)
    }

    /// Saves the grooming state to `vaultPath/.grooming-state.json`.
    public func save(vaultPath: URL) throws {
        let url = GroomingState.stateURL(vaultPath: vaultPath)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
