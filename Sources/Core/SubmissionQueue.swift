import Foundation

/// Serial queue for processing submitted ideas.
/// Serially runs each submission through the FilingAgent once one is configured.
public actor SubmissionQueue {
    public static let shared = SubmissionQueue()

    private var filingAgent: FilingAgent?
    private var vaultIndex: VaultIndex?

    private init() {}

    /// Configure the queue with the FilingAgent and VaultIndex.
    /// Call this after the vault path and LLM provider are known (e.g. at app launch).
    public func configure(filingAgent: FilingAgent, vaultIndex: VaultIndex) {
        self.filingAgent = filingAgent
        self.vaultIndex = vaultIndex
    }

    /// Submit a new idea text for processing.
    /// If a FilingAgent is configured, files the idea into the vault.
    /// Otherwise, logs the idea to stdout (fallback for unconfigured state).
    public func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let agent = filingAgent, let index = vaultIndex else {
            print("[BrainDump] Submitted idea (no agent configured): \(trimmed)")
            return
        }

        do {
            // Refresh index to pick up any recent vault changes, then search candidates
            await index.refresh()
            let candidates = await index.searchSimilar(query: trimmed, topK: 3)
            let summary = try await agent.file(rawInput: trimmed, candidates: candidates)
            print("[BrainDump] Filed: \(summary)")
        } catch FilingError.maxIterationsExceeded {
            print("[BrainDump] Error: filing agent exceeded max iterations for idea: \(trimmed.prefix(80))")
        } catch FilingError.llmError(let error) {
            print("[BrainDump] LLM error while filing: \(error.localizedDescription)")
        } catch {
            print("[BrainDump] Unexpected error while filing: \(error.localizedDescription)")
        }
    }
}
