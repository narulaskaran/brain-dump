import Foundation

/// Serial queue for processing submitted ideas.
/// Currently a stub — real filing logic arrives in Task 4.
public actor SubmissionQueue {
    public static let shared = SubmissionQueue()

    private init() {}

    /// Submit a new idea text for processing.
    /// - Parameter text: The raw idea text entered by the user.
    public func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        print("[BrainDump] Submitted idea: \(trimmed)")
    }
}
