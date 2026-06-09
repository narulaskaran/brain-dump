import Foundation

// MARK: - FilingError

public enum FilingError: Error, Sendable {
    case maxIterationsExceeded
    case sandboxViolation(String)
    case llmError(Error)
}

// MARK: - FilingAgent

/// Agentic loop that files a raw idea into an Obsidian vault using an LLM and vault tools.
public actor FilingAgent {
    private let provider: any LLMProvider
    private let vaultTools: VaultTools
    private let vaultPath: URL

    private static let maxIterations = 10

    public init(provider: any LLMProvider, vaultTools: VaultTools, vaultPath: URL) {
        self.provider = provider
        self.vaultTools = vaultTools
        self.vaultPath = vaultPath
    }

    /// File a raw idea into the vault.
    /// - Parameters:
    ///   - rawInput: The unprocessed idea text from the user.
    ///   - candidates: Top-3 semantically similar existing files (from VaultIndex).
    /// - Returns: The one-line summary from `done()`, or throws on failure.
    public func file(rawInput: String, candidates: [FileResult]) async throws -> String {
        let systemPrompt = buildSystemPrompt()
        let userMessage = buildUserMessage(rawInput: rawInput, candidates: candidates)

        var messages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: userMessage)
        ]

        let tools = vaultTools.toolDefinitions

        for _ in 0..<Self.maxIterations {
            let response: LLMResponse
            do {
                response = try await provider.complete(messages: messages, tools: tools)
            } catch {
                throw FilingError.llmError(error)
            }

            switch response {
            case .text(let text):
                // LLM returned plain text — treat as implicit completion
                messages.append(Message(role: .assistant, content: text))
                return text

            case .toolCalls(let calls):
                // Append the assistant's tool-call turn
                messages.append(Message(role: .assistant, toolUse: calls))

                var doneResult: String?

                // Execute each tool call and collect results
                for call in calls {
                    let result: String
                    do {
                        result = try await vaultTools.execute(call)
                    } catch let violation as FilingError {
                        throw violation
                    }

                    // Append the tool result
                    messages.append(Message(role: .tool, toolResultId: call.id, result: result))

                    if call.name == "done" {
                        doneResult = result
                    }
                }

                // If any call was `done`, end the loop
                if let summary = doneResult {
                    return summary
                }
            }
        }

        throw FilingError.maxIterationsExceeded
    }

    // MARK: - Prompt construction

    private func buildSystemPrompt() -> String {
        let existingGroups = discoverExistingGroups()
        let groupList = existingGroups.isEmpty ? "(none yet)" : existingGroups.joined(separator: ", ")

        return """
        You are filing a raw idea into an Obsidian vault at \(vaultPath.path).

        You have been given the top-3 most semantically similar existing files as starting context.
        Use the tools to read more files, search for others, or write/append as needed.

        EXISTING GROUPS: \(groupList)

        PARA ROUTING:
        - 10 Projects/<group>/<slug>.md — actionable, has an end goal
        - 20 Areas/<group>/<slug>.md — ongoing responsibility, no finish line
        - 30 Resources/<group>/<slug>.md — reference material, external knowledge
        - 00 Inbox/<slug>.md — genuinely unclear

        Rules:
        - Preserve the user's intent exactly. Don't add ideas they didn't have.
        - New files must follow the vault format contract: valid YAML frontmatter (tags: [<group>, seed]), [[wikilinks]] for cross-refs, ATX headings only, no HTML, no absolute paths.
        - Slug: lowercase-hyphenated, no stop words.
        - Use an existing group folder if one fits. Only create a new group if the idea clearly doesn't belong.
        - If input clearly extends an existing idea, append — don't duplicate.
        - If input spans multiple ideas, append to each.
        - Call update_index() when creating a new file.
        - Call done() when all writes are complete, with a one-line summary.

        NEW FILE TEMPLATE (use when creating a new .md file):
        ---
        tags: [<group>, seed]
        ---
        # <Title>

        **Status:** 🌱 seed
        **Project:** <group display name>
        **Created:** <YYYY-MM-DD>

        ---

        ## Problem

        <2-3 sentences>

        ---

        ## Core thesis

        <1-2 sentences>

        ---

        ## Open questions

        - [ ] <question>
        """
    }

    private func buildUserMessage(rawInput: String, candidates: [FileResult]) -> String {
        var parts: [String] = []
        parts.append("## Raw idea\n\n\(rawInput)")

        if !candidates.isEmpty {
            parts.append("## Top-3 similar existing files\n")
            for (i, candidate) in candidates.enumerated() {
                parts.append("""
                ### \(i + 1). \(candidate.title)
                **Path:** \(candidate.relativePath)
                **Score:** \(String(format: "%.4f", candidate.score))

                \(candidate.snippet)
                """)
            }
        } else {
            parts.append("## Top-3 similar existing files\n\n*(vault is empty or no similar files found)*")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Group discovery

    /// Enumerate existing group subfolders under the PARA folders.
    private func discoverExistingGroups() -> [String] {
        let paraFolders = ["10 Projects", "20 Areas", "30 Resources", "00 Inbox"]
        var groups: [String] = []
        let fm = FileManager.default

        for para in paraFolders {
            let paraURL = vaultPath.appendingPathComponent(para)
            guard let contents = try? fm.contentsOfDirectory(at: paraURL,
                                                              includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { continue }
            for url in contents {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    groups.append("\(para)/\(url.lastPathComponent)")
                }
            }
        }

        return groups.sorted()
    }
}
