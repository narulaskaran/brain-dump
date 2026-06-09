import SwiftUI

/// The SwiftUI view shown inside the popover for capturing a new idea.
struct IdeaInputView: View {
    let onSubmit: (String) -> Void
    let onDiscard: () -> Void

    @State private var text: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💡 New Idea")
                .font(.headline)
                .padding(.top, 4)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .focused($editorFocused)
                .onKeyPress(.escape) {
                    onDiscard()
                    return .handled
                }

            HStack {
                Spacer()
                Button("Discard") {
                    onDiscard()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("File Idea") {
                    onSubmit(text)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .onAppear {
            editorFocused = true
        }
    }
}
