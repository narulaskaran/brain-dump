import Foundation

/// Errors thrown when accessing the security-scoped vault resource.
public enum VaultAccessError: Error, Sendable {
    /// The OS refused to grant access to the security-scoped resource.
    case accessDenied
}

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

    // MARK: - Security-scoped resource access

    /// Wraps `work` inside a `startAccessingSecurityScopedResource` /
    /// `stopAccessingSecurityScopedResource` pair so that sandboxed builds can
    /// reach the user-chosen vault directory.
    ///
    /// If no bookmark is stored the closure is called with the fallback
    /// `effectiveVaultURL()` without starting a security-scoped access session
    /// (the URL is already accessible in that case).
    public static func withVaultAccess<T>(_ work: (URL) throws -> T) throws -> T {
        guard let url = resolvedVaultURL() else {
            return try work(effectiveVaultURL())
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultAccessError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try work(url)
    }

    /// Async variant of `withVaultAccess(_:)`.
    public static func withVaultAccess<T>(_ work: (URL) async throws -> T) async throws -> T {
        guard let url = resolvedVaultURL() else {
            return try await work(effectiveVaultURL())
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultAccessError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try await work(url)
    }
}
