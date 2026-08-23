import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct HistoryView: View {
    @ObservedObject var controller: AppController
    @State private var selection: UUID?
    @State private var displayedMonth = Calendar.current.startOfMonth(for: .now)
    @State private var exportMessage: String?
    @State private var entryPendingDeletion: HistoryEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                dateStrip

                if let entry = selectedEntry {
                    SessionHeaderCard(
                        entry: entry,
                        message: exportMessage,
                        retry: { controller.retry(entry) },
                        copy: { copy(entry) },
                        export: { export(entry) },
                        delete: { entryPendingDeletion = entry }
                    )
                    ReturnBriefView(entry: entry)
                } else {
                    ContentUnavailableView(
                        "履歴はまだありません",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Caps LockをONにすると退席記録を開始します。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 72)
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BrandPalette.BriefTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(BrandPalette.BriefTheme.signal)
        .navigationTitle("履歴")
        .confirmationDialog(
            "選択した履歴を削除しますか？",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let entry = entryPendingDeletion {
                    controller.delete(entry)
                }
                entryPendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                entryPendingDeletion = nil
            }
        }
        .onAppear {
            if !buckets.contains(where: { Calendar.current.isDate($0, equalTo: displayedMonth, toGranularity: .month) }),
               let newest = buckets.last {
                displayedMonth = Calendar.current.startOfMonth(for: newest)
            }
            if selection == nil || !entriesInDisplayedMonth.contains(where: { $0.id == selection }) {
                selection = entriesInDisplayedMonth.first?.id
            }
        }
        .onChange(of: controller.history) { _, entries in
            guard let selection else {
                self.selection = entries.first?.id
                return
            }
            if !entries.contains(where: { $0.id == selection }) {
                self.selection = entries.first?.id
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("履歴")
                .font(.system(size: 32, weight: .bold))

            if controller.isShowingDemoData {
                Text("デモデータ")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BrandPalette.BriefTheme.signal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        BrandPalette.BriefTheme.signal.opacity(0.12),
                        in: Capsule()
                    )
                    .padding(.leading, 6)
            }

            Spacer()

            Text(displayedMonth, format: .dateTime.year().month())
                .font(.headline.monospacedDigit())

            HStack(spacing: 4) {
                IconButton(systemName: "chevron.left") { shiftMonth(-1) }
                IconButton(systemName: "chevron.right") { shiftMonth(1) }
            }
        }
    }

    private var dateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(entriesByDayInMonth) { bucket in
                    DaySummaryCard(
                        bucket: bucket,
                        isSelected: isSelected(bucket),
                        select: {
                            selection = bucket.entries.first?.id
                        }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func copy(_ entry: HistoryEntry) {
        guard let summary = entry.summary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            SummaryMarkdown.document(summary, entry: entry),
            forType: .string
        )
        exportMessage = "コピーしました"
    }

    private func export(_ entry: HistoryEntry) {
        guard let summary = entry.summary else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "CapsStack-\(entry.interval.start.formatted(.dateTime.year().month().day().hour().minute())).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try SummaryMarkdown.document(summary, entry: entry)
                    .write(to: url, atomically: true, encoding: .utf8)
                exportMessage = "保存しました"
            } catch {
                exportMessage = "保存できませんでした"
            }
        }
    }

    private func shiftMonth(_ direction: Int) {
        guard let shifted = Calendar.current.date(
            byAdding: .month,
            value: direction,
            to: displayedMonth
        ) else { return }

        displayedMonth = Calendar.current.startOfMonth(for: shifted)
        selection = entriesInDisplayedMonth.first?.id
    }

    private var selectedEntry: HistoryEntry? {
        controller.history.first { $0.id == selection }
    }

    private var entriesInDisplayedMonth: [HistoryEntry] {
        controller.history.filter {
            Calendar.current.isDate($0.interval.end, equalTo: displayedMonth, toGranularity: .month)
        }
    }

    private var entriesByDayInMonth: [DayBucket] {
        Dictionary(grouping: entriesInDisplayedMonth) { entry in
            Calendar.current.startOfDay(for: entry.interval.end)
        }
        .map(DayBucket.init(dayStart:entries:))
        .sorted { $0.dayStart < $1.dayStart }
    }

    private var buckets: [Date] {
        Set(controller.history.map { Calendar.current.startOfDay(for: $0.interval.end) })
            .sorted()
    }

    private func isSelected(_ bucket: DayBucket) -> Bool {
        selectedEntry.map { entry in
            Calendar.current.isDate(entry.interval.end, inSameDayAs: bucket.dayStart)
        } ?? false
    }
}

private struct DayBucket: Identifiable {
    let dayStart: Date
    let entries: [HistoryEntry]

    var id: Date { dayStart }
    var sessionCount: Int { entries.reduce(0) { $0 + $1.sessionCount } }
    var duration: TimeInterval { entries.reduce(0) { $0 + $1.interval.duration } }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 7))
        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct DaySummaryCard: View {
    let bucket: DayBucket
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                Text(bucket.dayStart, format: .dateTime.day())
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? BrandPalette.BriefTheme.signal : .primary)

                Text(bucket.dayStart, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ActivityBars(entries: bucket.entries)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(bucket.sessionCount)件")
                        .font(.caption2.weight(.medium))
                    Text(Self.durationText(for: bucket.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 106, height: 148, alignment: .topLeading)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? BrandPalette.BriefTheme.signal : BrandPalette.BriefTheme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private static func durationText(for duration: TimeInterval) -> String {
        let totalMinutes = Int(max(0, duration)) / 60
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

private struct ActivityBars: View {
    let entries: [HistoryEntry]

    var body: some View {
        let maximum = entries.map(\.interval.duration).max() ?? 0

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(entries.prefix(8)) { entry in
                let ratio = maximum > 0 ? entry.interval.duration / maximum : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(ratio > 0 ? BrandPalette.BriefTheme.signal.opacity(0.28 + ratio * 0.42) : Color.white.opacity(0.08))
                    .frame(width: 5, height: max(6, ratio * 22))
            }
        }
        .frame(height: 22, alignment: .bottom)
    }
}

private struct SessionHeaderCard: View {
    let entry: HistoryEntry
    let message: String?
    let retry: () -> Void
    let copy: () -> Void
    let export: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Text("\(entry.interval.start, format: .dateTime.month().day().hour().minute()) - \(entry.interval.end, format: .dateTime.hour().minute())")
                .font(.body.monospacedDigit())

            Text(DurationFormatter.string(from: entry.interval.duration))
                .font(.title3.weight(.semibold).monospacedDigit())

            statusPill

            Spacer(minLength: 8)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                copy()
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button("Markdown書き出し", action: export)
                if entry.status == .pending {
                    Button("再要約", action: retry)
                }
                Divider()
                Button("削除", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(18)
        .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusPill: some View {
        switch entry.status {
        case .completed:
            Label("\(entry.sessionCount)セッション", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(BrandPalette.BriefTheme.signal)
        case .pending:
            Label("要約待ち", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.orange)
        case .empty:
            Label("対象なし", systemImage: "tray")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReturnBriefView: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 12) {
                Text("復帰ブリーフ")
                    .font(.system(size: 40, weight: .bold))

                if let summary = entry.summary {
                    Text(summary.overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }

            if let summary = entry.summary {
                BriefSection(
                    title: "進捗",
                    symbolName: "scope",
                    items: summary.progress,
                    checklist: false
                )
                BriefSection(
                    title: "決定",
                    symbolName: "checkmark",
                    items: summary.decisions,
                    checklist: false
                )
                BriefSection(
                    title: "次の一手",
                    symbolName: "arrow.right",
                    items: summary.nextSteps,
                    checklist: true
                )

                if !summary.currentState.isEmpty || !summary.blockers.isEmpty {
                    supplementalSections(summary)
                }
            } else if entry.status == .pending {
                VStack(alignment: .leading, spacing: 10) {
                    Label("要約できませんでした", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(entry.errorMessage ?? "要約CLIを確認して再試行してください。")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                ContentUnavailableView("対象セッションなし", systemImage: "tray")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let memo = entry.quickMemo, !memo.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("退席前メモ", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                    Text(memo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandPalette.BriefTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            }

            if !entry.collectionIssues.isEmpty {
                BriefSection(
                    title: "収集時の注意",
                    symbolName: "info",
                    items: entry.collectionIssues.map { "\($0.provider.displayName): \($0.message)" },
                    checklist: false
                )
            }

            footer
        }
    }

    @ViewBuilder
    private func supplementalSections(_ summary: SummaryDocument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !summary.currentState.isEmpty {
                CompactList(title: "現在の状態", items: summary.currentState)
            }
            if !summary.blockers.isEmpty {
                CompactList(title: "問題・確認待ち", items: summary.blockers)
            }
        }
    }

    private var footer: some View {
        let characters = entry.summary.map { SummaryMarkdown.document($0, entry: entry).count } ?? 0
        let characterCount = NumberFormatter.localizedString(
            from: NSNumber(value: characters),
            number: .decimal
        )

        return HStack(spacing: 8) {
            Text("作成: \(entry.interval.end, format: .dateTime.year().month().day().hour().minute())")
            Text("|").foregroundStyle(.tertiary)
            Text("モデル: \(entry.provider?.displayName ?? "未設定")")
            Text("|").foregroundStyle(.tertiary)
            Text("文字数: \(characterCount)")
            if entry.fallbackUsed {
                Text("|").foregroundStyle(.tertiary)
                Text("フォールバック使用")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

private struct BriefSection: View {
    let title: String
    let symbolName: String
    let items: [String]
    let checklist: Bool

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: symbolName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BrandPalette.BriefTheme.signal)
                        .frame(width: 17, height: 17)
                        .background(BrandPalette.BriefTheme.signal.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.subheadline.weight(.bold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: checklist ? "square" : "circle.fill")
                                .font(.system(size: checklist ? 11 : 4, weight: .regular))
                                .foregroundStyle(BrandPalette.BriefTheme.signal)
                                .padding(.top, checklist ? 1 : 5)

                            Text(item)
                                .font(.callout)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

private struct CompactList: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 3, height: 3)
                    Text(item)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
