import Foundation

/// Serial queue for processing submitted ideas.
/// Serially runs each submission through the FilingAgent once one is configured.
public actor SubmissionQueue {
    public static let shared = SubmissionQueue()

    private var filingAgent: FilingAgent?
    private var groomingAgent: GroomingAgent?
    private var vaultIndex: VaultIndex?

    /// Called on the main actor whenever the processing state changes.
    /// Wire this in StatusBarController to drive icon transitions.
    public var onStateChange: (@MainActor @Sendable (MenuBarIconState) -> Void)?

    private init() {}

    /// Configure the queue with the agents and VaultIndex.
    /// Call this after the vault path and LLM provider are known (e.g. at app launch).
    public func configure(
        filingAgent: FilingAgent,
        groomingAgent: GroomingAgent,
        vaultIndex: VaultIndex
    ) {
        self.filingAgent = filingAgent
        self.groomingAgent = groomingAgent
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

        await notifyStateChange(.processing)

        do {
            // Refresh index to pick up any recent vault changes, then search candidates
            await index.refresh()
            let candidates = await index.searchSimilar(query: trimmed, topK: 3)
            let summary = try await agent.file(rawInput: trimmed, candidates: candidates)
            print("[BrainDump] Filed: \(summary)")

            // Auto-groom if enabled
            if UserDefaults.standard.bool(forKey: "autoGroom"), let groomer = groomingAgent {
                do {
                    let count = try await groomer.groom()
                    print("[BrainDump] Auto-groom complete: \(count) findings")
                } catch {
                    print("[BrainDump] Auto-groom error: \(error.localizedDescription)")
                    // Non-fatal: filing succeeded, report done anyway
                }
            }

            await notifyStateChange(.done)
        } catch FilingError.maxIterationsExceeded {
            print("[BrainDump] Error: filing agent exceeded max iterations for idea: \(trimmed.prefix(80))")
            await notifyStateChange(.error("Filing timed out — try again"))
        } catch FilingError.llmError(let error) {
            print("[BrainDump] LLM error while filing: \(error.localizedDescription)")
            await notifyStateChange(.error("LLM error: \(error.localizedDescription)"))
        } catch {
            print("[BrainDump] Unexpected error while filing: \(error.localizedDescription)")
            await notifyStateChange(.error(error.localizedDescription))
        }
    }

    /// Run a manual grooming pass and push state transitions to the observer.
    public func runGrooming() async {
        guard let groomer = groomingAgent else {
            print("[BrainDump] Groom requested but no GroomingAgent configured")
            return
        }

        await notifyStateChange(.processing)
        do {
            let count = try await groomer.groom()
            print("[BrainDump] Groom complete: \(count) findings")
            await notifyStateChange(.done)
        } catch {
            print("[BrainDump] Groom error: \(error.localizedDescription)")
            await notifyStateChange(.error("Groom failed: \(error.localizedDescription)"))
        }
    }

    /// Sets the state-change callback. Use this from outside the actor to register observers.
    public func setOnStateChange(_ callback: (@MainActor @Sendable (MenuBarIconState) -> Void)?) {
        self.onStateChange = callback
    }

    // MARK: - Helpers

    private func notifyStateChange(_ state: MenuBarIconState) async {
        guard let callback = onStateChange else { return }
        await MainActor.run { callback(state) }
    }
}
