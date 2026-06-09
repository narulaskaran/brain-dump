import Foundation

/// The 6 tools the LLM can call to interact with the Obsidian vault.
public struct VaultTools: Sendable {
    let vaultPath: URL
    let vaultIndex: VaultIndex

    public init(vaultPath: URL, vaultIndex: VaultIndex) {
        self.vaultPath = vaultPath
        self.vaultIndex = vaultIndex
    }

    // MARK: - Tool Definitions

    public var toolDefinitions: [Tool] {
        [
            Tool(
                name: "search_similar",
                description: "Search the vault for files semantically similar to a query. Returns the top-3 most relevant files.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("The search query text")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "read_file",
                description: "Read the full content of a file in the vault. Path is relative to vault root.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Path to the file, relative to vault root (e.g. '10 Projects/swift-dev/my-idea.md')")
                        ])
                    ]),
                    "required": .array([.string("path")])
                ])
            ),
            Tool(
                name: "write_file",
                description: "Create a new file in the vault with the given content. Returns an error if the file already exists — use append_to_file instead. Creates intermediate directories as needed.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Path relative to vault root")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Full file content to write")
                        ])
                    ]),
                    "required": .array([.string("path"), .string("content")])
                ])
            ),
            Tool(
                name: "append_to_file",
                description: "Append content to an existing file in the vault. Creates the file if it does not exist.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Path relative to vault root")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Content to append")
                        ])
                    ]),
                    "required": .array([.string("path"), .string("content")])
                ])
            ),
            Tool(
                name: "update_index",
                description: "Append a row to IDEAS.md at the vault root. The row must follow the format: | [[link]] | description | tags |. Creates IDEAS.md with a header if it does not exist.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "row": .object([
                            "type": .string("string"),
                            "description": .string("A table row in the format: | [[link]] | description | tags |")
                        ])
                    ]),
                    "required": .array([.string("row")])
                ])
            ),
            Tool(
                name: "done",
                description: "Signal that all filing is complete. Call this when all writes are finished. Returns the summary.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "summary": .object([
                            "type": .string("string"),
                            "description": .string("One-line summary of what was filed")
                        ])
                    ]),
                    "required": .array([.string("summary")])
                ])
            )
        ]
    }

    // MARK: - Execution

    /// Execute a tool call and return the result string.
    public func execute(_ call: ToolCall) async throws -> String {
        switch call.name {
        case "search_similar":
            return await executeSearchSimilar(call.input)
        case "read_file":
            return try executeReadFile(call.input)
        case "write_file":
            return try await executeWriteFile(call.input)
        case "append_to_file":
            return try executeAppendToFile(call.input)
        case "update_index":
            return executeUpdateIndex(call.input)
        case "done":
            return executeDone(call.input)
        default:
            return "Error: unknown tool '\(call.name)'"
        }
    }

    // MARK: - Individual tool implementations

    private func executeSearchSimilar(_ input: JSONValue) async -> String {
        guard case .object(let obj) = input,
              case .string(let query) = obj["query"] else {
            return "Error: missing required parameter 'query'"
        }

        let results = await vaultIndex.searchSimilar(query: query, topK: 3)

        // Build JSON array result
        let items: [String] = results.map { r in
            let escapedPath = r.relativePath.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedTitle = r.title.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedSnippet = r.snippet
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            let score = String(format: "%.4f", r.score)
            return """
            {"path":"\(escapedPath)","title":"\(escapedTitle)","snippet":"\(escapedSnippet)","score":\(score)}
            """
        }
        return "[\(items.joined(separator: ","))]"
    }

    private func executeReadFile(_ input: JSONValue) throws -> String {
        guard case .object(let obj) = input,
              case .string(let path) = obj["path"] else {
            return "Error: missing required parameter 'path'"
        }

        return try withVaultAccessThrows { vaultURL in
            guard let resolvedURL = resolveAndValidate(path: path, vaultURL: vaultURL) else {
                throw FilingError.sandboxViolation(path)
            }
            do {
                return try String(contentsOf: resolvedURL, encoding: .utf8)
            } catch {
                return "Error: could not read file at '\(path)': \(error.localizedDescription)"
            }
        }
    }

    private func executeWriteFile(_ input: JSONValue) async throws -> String {
        guard case .object(let obj) = input,
              case .string(let path) = obj["path"],
              case .string(let content) = obj["content"] else {
            return "Error: missing required parameters 'path' and/or 'content'"
        }

        return try await withVaultAccessAsyncThrows { vaultURL in
            guard let resolvedURL = resolveAndValidate(path: path, vaultURL: vaultURL) else {
                throw FilingError.sandboxViolation(path)
            }

            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                return "Error: file exists, use append_to_file"
            }

            // Create intermediate directories
            let dir = resolvedURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return "Error: could not create directories for '\(path)': \(error.localizedDescription)"
            }

            do {
                try content.write(to: resolvedURL, atomically: true, encoding: .utf8)
                // Reindex the new file so future searches can find it
                await vaultIndex.reindex(file: resolvedURL)

                // Sync graph colours if this file landed in a group subfolder
                if isInGroupSubfolder(path: path) {
                    try? ObsidianGraphConfig.sync(vaultPath: vaultURL)
                }

                return "OK: file written to '\(path)'"
            } catch {
                return "Error: could not write file at '\(path)': \(error.localizedDescription)"
            }
        }
    }

    /// Returns true when `path` is at least 3 components deep and its top-level
    /// folder is one of the PARA root folders (e.g. "10 Projects/group/file.md").
    private func isInGroupSubfolder(path: String) -> Bool {
        let paraFolders = ["10 Projects", "20 Areas", "30 Resources", "00 Inbox"]
        let parts = path.components(separatedBy: "/")
        guard parts.count >= 3 else { return false }
        return paraFolders.contains(parts[0])
    }

    private func executeAppendToFile(_ input: JSONValue) throws -> String {
        guard case .object(let obj) = input,
              case .string(let path) = obj["path"],
              case .string(let content) = obj["content"] else {
            return "Error: missing required parameters 'path' and/or 'content'"
        }

        return try withVaultAccessThrows { vaultURL in
            guard let resolvedURL = resolveAndValidate(path: path, vaultURL: vaultURL) else {
                throw FilingError.sandboxViolation(path)
            }

            // Create intermediate directories if needed
            let dir = resolvedURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return "Error: could not create directories for '\(path)': \(error.localizedDescription)"
            }

            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                // Append to existing file
                do {
                    let existing = try String(contentsOf: resolvedURL, encoding: .utf8)
                    let newContent = existing + content
                    try newContent.write(to: resolvedURL, atomically: true, encoding: .utf8)
                    return "OK: content appended to '\(path)'"
                } catch {
                    return "Error: could not append to file at '\(path)': \(error.localizedDescription)"
                }
            } else {
                // Create new file with content
                do {
                    try content.write(to: resolvedURL, atomically: true, encoding: .utf8)
                    return "OK: file created with content at '\(path)'"
                } catch {
                    return "Error: could not create file at '\(path)': \(error.localizedDescription)"
                }
            }
        }
    }

    private func executeUpdateIndex(_ input: JSONValue) -> String {
        guard case .object(let obj) = input,
              case .string(let row) = obj["row"] else {
            return "Error: missing required parameter 'row'"
        }

        // Validate row format: must match | [[...]] | ... | ... |
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"),
              trimmed.hasSuffix("|"),
              trimmed.contains("[["),
              trimmed.contains("]]") else {
            return "Error: row format invalid — must match | [[link]] | description | tags |"
        }

        return withVaultAccess { vaultURL in
            let ideasURL = vaultURL.appendingPathComponent("IDEAS.md")
            let fm = FileManager.default

            if !fm.fileExists(atPath: ideasURL.path) {
                // Create IDEAS.md with header
                let header = """
                # Ideas Index

                | File | Description | Tags |
                |------|-------------|------|
                """
                do {
                    try header.write(to: ideasURL, atomically: true, encoding: .utf8)
                } catch {
                    return "Error: could not create IDEAS.md: \(error.localizedDescription)"
                }
            }

            do {
                let existing = try String(contentsOf: ideasURL, encoding: .utf8)
                let newContent = existing + "\n" + trimmed
                try newContent.write(to: ideasURL, atomically: true, encoding: .utf8)
                return "OK: index row added to IDEAS.md"
            } catch {
                return "Error: could not update IDEAS.md: \(error.localizedDescription)"
            }
        }
    }

    private func executeDone(_ input: JSONValue) -> String {
        guard case .object(let obj) = input,
              case .string(let summary) = obj["summary"] else {
            return "Error: missing required parameter 'summary'"
        }
        return summary
    }

    // MARK: - Security-scope helpers

    /// Run synchronous vault I/O inside a security-scoped resource session.
    private func withVaultAccess(_ work: (URL) throws -> String) -> String {
        do {
            return try VaultPathManager.withVaultAccess(work)
        } catch VaultAccessError.accessDenied {
            return "Error: access denied to vault (security-scoped resource)"
        } catch {
            return "Error: vault access failed: \(error.localizedDescription)"
        }
    }

    /// Throwing variant of `withVaultAccess(_:)` that propagates errors.
    private func withVaultAccessThrows(_ work: (URL) throws -> String) throws -> String {
        do {
            return try VaultPathManager.withVaultAccess(work)
        } catch let error as FilingError {
            throw error
        } catch VaultAccessError.accessDenied {
            return "Error: access denied to vault (security-scoped resource)"
        } catch {
            return "Error: vault access failed: \(error.localizedDescription)"
        }
    }

    /// Async variant of `withVaultAccess(_:)`.
    private func withVaultAccessAsync(_ work: (URL) async throws -> String) async -> String {
        do {
            return try await VaultPathManager.withVaultAccess(work)
        } catch VaultAccessError.accessDenied {
            return "Error: access denied to vault (security-scoped resource)"
        } catch {
            return "Error: vault access failed: \(error.localizedDescription)"
        }
    }

    /// Throwing async variant of `withVaultAccessAsync(_:)` that propagates errors.
    private func withVaultAccessAsyncThrows(_ work: (URL) async throws -> String) async throws -> String {
        do {
            return try await VaultPathManager.withVaultAccess(work)
        } catch let error as FilingError {
            throw error
        } catch VaultAccessError.accessDenied {
            return "Error: access denied to vault (security-scoped resource)"
        } catch {
            return "Error: vault access failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sandbox helpers

    /// Resolve `path` (relative or absolute) to an absolute URL and verify it
    /// is within the given vault URL. Returns nil if the path is outside the vault.
    private func resolveAndValidate(path: String, vaultURL: URL) -> URL? {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        } else {
            url = vaultURL.appendingPathComponent(path).resolvingSymlinksInPath()
        }
        let vaultResolved = vaultURL.resolvingSymlinksInPath()
        // Ensure the resolved path has the vault path as a prefix
        guard url.path.hasPrefix(vaultResolved.path + "/") ||
              url.path == vaultResolved.path else {
            return nil
        }
        return url
    }
}
