import Foundation

/// Manages an in-memory semantic index of Markdown files in a vault directory.
public actor VaultIndex {

    private let vaultPath: URL
    private let engine: EmbeddingEngine
    private var cache: EmbeddingCache

    // In-memory map from absolute path -> (mtime, vector, content snippet, title)
    private struct FileRecord {
        var mtimeInterval: TimeInterval
        var vector: [Double]
        var title: String
        var snippet: String
    }
    private var records: [String: FileRecord] = [:]

    public init(vaultPath: URL, embeddingEngine: EmbeddingEngine) {
        self.vaultPath = vaultPath
        self.engine = embeddingEngine
        self.cache = EmbeddingCache()
    }

    // MARK: - Refresh

    /// Scans the vault for `.md` files, refreshes stale embeddings, and saves the cache.
    public func refresh() async {
        // Acquire the vault URL and start accessing the security-scoped resource.
        // We manage the lifecycle manually here so that actor-isolated async work
        // can happen between start and stop without sending `self` across isolation.
        let vaultURL: URL
        let needsStop: Bool
        if let resolved = VaultPathManager.resolvedVaultURL() {
            guard resolved.startAccessingSecurityScopedResource() else {
                print("[VaultIndex] refresh: access denied to security-scoped vault resource")
                return
            }
            vaultURL = resolved
            needsStop = true
        } else {
            vaultURL = VaultPathManager.effectiveVaultURL()
            needsStop = false
        }
        defer {
            if needsStop { vaultURL.stopAccessingSecurityScopedResource() }
        }

        cache = EmbeddingCache.load(vaultPath: vaultURL)

        let mdFiles = findMarkdownFiles(in: vaultURL)
        var cacheChanged = false

        for fileURL in mdFiles {
            let path = fileURL.path
            guard let liveMtime = modificationDateInterval(of: path) else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let snippet = String(content.prefix(500))
            let title = extractTitle(from: content, fileURL: fileURL)

            // Use cached vector if mtime matches within 1-second tolerance
            if let entry = cache.entries[path], abs(entry.mtimeInterval - liveMtime) < 1.0 {
                records[path] = FileRecord(
                    mtimeInterval: liveMtime,
                    vector: entry.vector,
                    title: title,
                    snippet: snippet
                )
            } else {
                // Recompute embedding: title + up to 500 chars of content
                let inputText = title + " " + String(content.prefix(500))
                let vector = await engine.embed(inputText)
                records[path] = FileRecord(
                    mtimeInterval: liveMtime,
                    vector: vector,
                    title: title,
                    snippet: snippet
                )
                cache.entries[path] = EmbeddingCache.Entry(mtimeInterval: liveMtime, vector: vector)
                cacheChanged = true
            }
        }

        // Remove stale cache entries for files that no longer exist
        let livePaths = Set(mdFiles.map(\.path))
        for key in cache.entries.keys where !livePaths.contains(key) {
            cache.entries.removeValue(forKey: key)
            records.removeValue(forKey: key)
            cacheChanged = true
        }

        if cacheChanged {
            try? cache.save(vaultPath: vaultURL)
        }
    }

    // MARK: - Search

    /// Embeds `query` and returns the top-`topK` files sorted by descending cosine similarity.
    public func searchSimilar(query: String, topK: Int = 3) async -> [FileResult] {
        let queryVector = await engine.embed(query)
        guard !queryVector.isEmpty else { return [] }

        var scored: [(path: String, score: Double)] = []
        for (path, record) in records where !record.vector.isEmpty {
            let score = await engine.cosineSimilarity(queryVector, record.vector)
            scored.append((path: path, score: score))
        }

        scored.sort { $0.score > $1.score }
        let topResults = scored.prefix(topK)

        return topResults.compactMap { item in
            guard let record = records[item.path] else { return nil }
            let relativePath = relativize(path: item.path)
            return FileResult(
                path: item.path,
                relativePath: relativePath,
                title: record.title,
                snippet: record.snippet,
                score: item.score
            )
        }
    }

    // MARK: - Bulk accessors

    /// Returns all indexed files as FileResult values with a score of 1.0.
    public func allFiles() -> [FileResult] {
        records.map { (path, record) in
            let relativePath = relativize(path: path)
            return FileResult(
                path: path,
                relativePath: relativePath,
                title: record.title,
                snippet: record.snippet,
                score: 1.0
            )
        }
    }

    /// Returns all cached embedding vectors keyed by absolute path.
    public func allVectors() -> [String: [Double]] {
        records.reduce(into: [:]) { dict, pair in
            dict[pair.key] = pair.value.vector
        }
    }

    /// Returns the mtime interval for a given absolute path, or nil if not indexed.
    public func mtimeInterval(for path: String) -> TimeInterval? {
        records[path]?.mtimeInterval
    }

    // MARK: - Reindex single file

    /// Recomputes and caches the embedding for a single file.
    /// Call this after writing a new or updated file to the vault.
    public func reindex(file: URL) async {
        // Manage security-scoped access manually (same reason as refresh()).
        let vaultURL: URL
        let needsStop: Bool
        if let resolved = VaultPathManager.resolvedVaultURL() {
            guard resolved.startAccessingSecurityScopedResource() else {
                print("[VaultIndex] reindex: access denied to security-scoped vault resource")
                return
            }
            vaultURL = resolved
            needsStop = true
        } else {
            vaultURL = VaultPathManager.effectiveVaultURL()
            needsStop = false
        }
        defer {
            if needsStop { vaultURL.stopAccessingSecurityScopedResource() }
        }

        let path = file.path
        guard let liveMtime = modificationDateInterval(of: path) else { return }
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return }

        let snippet = String(content.prefix(500))
        let title = extractTitle(from: content, fileURL: file)
        let inputText = title + " " + String(content.prefix(500))
        let vector = await engine.embed(inputText)

        records[path] = FileRecord(mtimeInterval: liveMtime, vector: vector, title: title, snippet: snippet)
        cache.entries[path] = EmbeddingCache.Entry(mtimeInterval: liveMtime, vector: vector)
        try? cache.save(vaultPath: vaultURL)
    }

    // MARK: - Helpers

    /// Recursively enumerates `.md` files, skipping dotfiles and dotdirectories.
    private func findMarkdownFiles(in directory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            // Skip dot-prefixed directory entries (e.g. .obsidian)
            let name = fileURL.lastPathComponent
            if name.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            results.append(fileURL)
        }
        return results
    }

    /// Returns the modification date of a file as a TimeInterval (seconds since
    /// reference date), preserving sub-second precision. Returns nil if unavailable.
    private func modificationDateInterval(of path: String) -> TimeInterval? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate
    }

    /// Extracts the first ATX H1 heading (`# Heading`) or derives a title from the filename.
    private func extractTitle(from content: String, fileURL: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let heading = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { return heading }
            }
        }
        // Fall back to filename stem
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return stem
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Returns the path relative to the vault root.
    private func relativize(path: String) -> String {
        let vaultPrefix = vaultPath.path
        if path.hasPrefix(vaultPrefix) {
            var relative = String(path.dropFirst(vaultPrefix.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return path
    }
}
