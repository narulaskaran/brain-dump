import Foundation

/// Analyzes the vault for backlog health: near-duplicates, promotion candidates,
/// and missing categories. Writes findings to GROOMING.md and .grooming-state.json.
public actor GroomingAgent {
    private let provider: any LLMProvider
    private let vaultIndex: VaultIndex
    private let vaultPath: URL

    private static let similarityThreshold: Double = 0.85
    private static let chunkSize: Int = 50

    private static let systemPrompt = """
    You are reviewing an Obsidian ideas vault for backlog health.

    You have been given file summaries and their paths.
    High-similarity pairs (cosine similarity > 0.85) have been pre-flagged as near-duplicates.

    Identify and write findings in this exact format:
    ## Near-duplicates
    - [[path/to/a]] and [[path/to/b]]: <one-line rationale>

    ## Ready to promote
    - [[path/to/file]]: <why it's ready to move from 🌱 seed → 🔄 active>

    ## Missing categories
    - <theme>: [[file1]], [[file2]], [[file3]] — <one-line observation>

    Rules:
    - Be terse. One bullet per finding.
    - Flag only high-confidence observations.
    - Do NOT suggest modifying files — suggestions only.
    - Return ONLY the markdown findings, no preamble.
    """

    public init(provider: any LLMProvider, vaultIndex: VaultIndex, vaultPath: URL) {
        self.provider = provider
        self.vaultIndex = vaultIndex
        self.vaultPath = vaultPath
    }

    /// Run a full grooming pass. Returns number of findings written.
    public func groom() async throws -> Int {
        // 1. Refresh the index
        await vaultIndex.refresh()

        // 2. Retrieve all files and vectors
        let allFiles = await vaultIndex.allFiles()
        let allVectors = await vaultIndex.allVectors()

        guard !allFiles.isEmpty else {
            // Nothing to groom — write an empty GROOMING.md and state
            let state = GroomingState(reviewed: false, generatedAt: Date(), count: 0)
            try state.save(vaultPath: vaultPath)
            return 0
        }

        // 3. Compute pairwise cosine similarity to find near-duplicates
        let nearDuplicates = computeNearDuplicates(vectors: allVectors)

        // 4. Sort files by most-recently-modified (descending), chunk into groups of 50
        let sortedFiles = await sortedByMtime(files: allFiles)
        let chunks = stride(from: 0, to: sortedFiles.count, by: Self.chunkSize).map {
            Array(sortedFiles[$0..<min($0 + Self.chunkSize, sortedFiles.count)])
        }

        // 5. Call LLM for each chunk
        var chunkOutputs: [String] = []
        for chunk in chunks {
            let output = try await reviewChunk(chunk, nearDuplicates: nearDuplicates)
            chunkOutputs.append(output)
        }

        // 6. Count findings (lines starting with "- ")
        let allOutput = chunkOutputs.joined(separator: "\n\n")
        let findingCount = allOutput
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
            .count

        // 7. Write GROOMING.md
        let iso8601 = ISO8601DateFormatter().string(from: Date())
        let header = """
        # Grooming — \(iso8601)

        _\(findingCount) findings across \(allFiles.count) files. Act on suggestions in Obsidian, then delete this file._

        """
        let groomingContent = header + chunkOutputs.joined(separator: "\n\n")
        let groomingURL = vaultPath.appendingPathComponent("GROOMING.md")
        try groomingContent.write(to: groomingURL, atomically: true, encoding: .utf8)

        // 8. Save .grooming-state.json
        let state = GroomingState(reviewed: false, generatedAt: Date(), count: findingCount)
        try state.save(vaultPath: vaultPath)

        return findingCount
    }

    // MARK: - Near-duplicate detection

    private func computeNearDuplicates(vectors: [String: [Double]]) -> [(String, String)] {
        let paths = Array(vectors.keys)
        var pairs: [(String, String)] = []

        for i in 0..<paths.count {
            for j in (i + 1)..<paths.count {
                let a = paths[i]
                let b = paths[j]
                guard let va = vectors[a], let vb = vectors[b] else { continue }
                let score = cosineSimilarity(va, vb)
                if score > Self.similarityThreshold {
                    pairs.append((a, b))
                }
            }
        }
        return pairs
    }

    /// Pure cosine similarity — avoids a cross-actor hop to EmbeddingEngine.
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty, a.count == b.count else { return 0 }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    // MARK: - Sorting

    private func sortedByMtime(files: [FileResult]) async -> [FileResult] {
        // Gather mtime for each file
        var withMtime: [(FileResult, TimeInterval)] = []
        for file in files {
            let mtime = await vaultIndex.mtimeInterval(for: file.path) ?? 0
            withMtime.append((file, mtime))
        }
        // Sort descending by mtime
        return withMtime
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: - LLM call

    private func reviewChunk(_ files: [FileResult], nearDuplicates: [(String, String)]) async throws -> String {
        var userMessage = "## Files in this batch\n\n"
        for file in files {
            userMessage += "### \(file.title)\n**Path:** \(file.relativePath)\n\n\(file.snippet)\n\n"
        }

        // Append near-duplicate pairs relevant to this chunk
        let chunkPaths = Set(files.map { $0.path })
        let relevantPairs = nearDuplicates.filter { chunkPaths.contains($0.0) || chunkPaths.contains($0.1) }
        if !relevantPairs.isEmpty {
            userMessage += "## Pre-flagged near-duplicate pairs (cosine > 0.85)\n\n"
            for (a, b) in relevantPairs {
                let relA = relativize(path: a)
                let relB = relativize(path: b)
                userMessage += "- [[\(relA)]] and [[\(relB)]]\n"
            }
        }

        let messages: [Message] = [
            Message(role: .system, content: Self.systemPrompt),
            Message(role: .user, content: userMessage)
        ]

        let response = try await provider.complete(messages: messages, tools: [])
        switch response {
        case .text(let text):
            return text
        case .toolCalls:
            // Grooming prompt never requests tools; treat as empty
            return ""
        }
    }

    // MARK: - Helpers

    private func relativize(path: String) -> String {
        let prefix = vaultPath.path
        if path.hasPrefix(prefix) {
            var rel = String(path.dropFirst(prefix.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            return rel
        }
        return path
    }
}
