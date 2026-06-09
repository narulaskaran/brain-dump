import Foundation

/// Manages the user-chosen vault directory, persisted as a security-scoped bookmark.
public struct VaultPathManager {

    private static let defaultsKey = "vaultBookmark"

    private init() {}

    // MARK: - Public API

    /// Resolve the stored security-scoped bookmark to a URL.
    /// Returns `nil` if no bookmark is stored or if the bookmark is stale.
    public static func resolvedVaultURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            // Attempt to refresh the bookmark in place
            _ = try? storeBookmark(for: url)
        }
        return url
    }

    /// Store a new security-scoped bookmark for the given URL (chosen via NSOpenPanel).
    @discardableResult
    public static func storeBookmark(for url: URL) throws -> Data {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: defaultsKey)
        return data
    }

    /// Returns the resolved vault URL, or `~/ideas/` if no bookmark is stored.
    public static func effectiveVaultURL() -> URL {
        resolvedVaultURL() ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("ideas", isDirectory: true)
    }
}
