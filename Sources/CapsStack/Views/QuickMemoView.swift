import CapsStackLocalization
import SwiftUI

struct QuickMemoView: View {
    @AppStorage(PreferenceKeys.quickMemo) private var quickMemoText = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrandPalette.BriefTheme.signal)
                    .frame(width: 34, height: 34)
                    .background(
                        BrandPalette.BriefTheme.signal.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(CapsStackText.resource(.awayMemo))
                        .font(.title3.bold())

                    Text(CapsStackText.resource(.quickMemoDescription))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(BrandPalette.BriefTheme.card)

                if quickMemoText.isEmpty {
                    Text(CapsStackText.resource(.quickMemoPlaceholder))
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $quickMemoText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($isEditorFocused)
                    .accessibilityLabel(CapsStackText.resolve(.awayMemo))
            }
            .frame(width: 420, height: 144)
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button(CapsStackText.resource(.clear), role: .destructive) {
                    quickMemoText = ""
                }
                .disabled(quickMemoText.isEmpty)

                Label(CapsStackText.resource(.savedAutomaticallyOnThisMac), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(CapsStackText.resource(.done)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .fixedSize()
        .background(BrandPalette.BriefTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(BrandPalette.BriefTheme.signal)
        .onAppear {
            isEditorFocused = true
        }
        .onChange(of: quickMemoText) { _, newValue in
            let bounded = QuickMemoPreferences.boundedText(newValue)
            if bounded != newValue { quickMemoText = bounded }
        }
    }
}
