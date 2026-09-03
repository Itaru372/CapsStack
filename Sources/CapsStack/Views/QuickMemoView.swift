import SwiftUI

struct QuickMemoView: View {
    @AppStorage(PreferenceKeys.quickMemo) private var quickMemoText = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Away memo")
                    .font(.headline)

                Text("Add context for work that is not captured in logs, such as GUI apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $quickMemoText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(width: 400, height: 120)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .focused($isEditorFocused)
                .accessibilityLabel("Away memo")

            HStack {
                Button("Clear", role: .destructive) {
                    quickMemoText = ""
                }
                .disabled(quickMemoText.isEmpty)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .fixedSize()
        .onAppear {
            isEditorFocused = true
        }
        .onChange(of: quickMemoText) { _, newValue in
            let bounded = QuickMemoPreferences.boundedText(newValue)
            if bounded != newValue { quickMemoText = bounded }
        }
    }
}
