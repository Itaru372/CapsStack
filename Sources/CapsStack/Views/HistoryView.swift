import SwiftUI

struct HistoryView: View {
    @ObservedObject var controller: AppController
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(controller.history, selection: $selection) { entry in
                HistoryRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu {
                        Button("削除", role: .destructive) {
                            controller.delete(entry)
                        }
                    }
            }
            .listStyle(.sidebar)
            .navigationTitle("退席履歴")
            .overlay {
                if controller.history.isEmpty {
                    ContentUnavailableView(
                        "履歴はまだありません",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Caps LockをONにすると退席記録を開始します。")
                    )
                }
            }
        } detail: {
            if let entry = selectedEntry {
                HistoryDetailView(entry: entry, retry: { controller.retry(entry) })
            } else {
                ContentUnavailableView("履歴を選択", systemImage: "sidebar.left")
            }
        }
        .onAppear {
            if selection == nil { selection = controller.history.first?.id }
        }
        .onChange(of: controller.history) { _, entries in
            if let selection, entries.contains(where: { $0.id == selection }) { return }
            selection = entries.first?.id
        }
        .tint(BrandPalette.petrolSlate)
    }

    private var selectedEntry: HistoryEntry? {
        controller.history.first { $0.id == selection }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.interval.start, format: .dateTime.month().day().hour().minute())
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        switch entry.status {
        case .completed: entry.summary?.overview ?? "要約完了"
        case .pending: "要約待ち — 再試行できます"
        case .empty: "対象セッションなし"
        }
    }

    private var icon: String {
        switch entry.status {
        case .completed: "checkmark.circle.fill"
        case .pending: "exclamationmark.circle.fill"
        case .empty: "minus.circle"
        }
    }

    private var color: Color {
        switch entry.status {
        case .completed: BrandPalette.petrolSlate
        case .pending: BrandPalette.agedBrass
        case .empty: .secondary
        }
    }
}

private struct HistoryDetailView: View {
    let entry: HistoryEntry
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.interval.start, format: .dateTime.year().month().day().hour().minute())
                            .font(.title2.bold())
                        Text("\(DurationFormatter.string(from: entry.interval.duration))・\(entry.sessionCount)セッション")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let provider = entry.provider {
                        Label(provider.displayName, systemImage: provider.systemImage)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BrandPalette.bone, in: Capsule())
                    }
                }

                if let summary = entry.summary {
                    Text(summary.overview)
                        .font(.title3)
                        .textSelection(.enabled)
                    SummaryListSection(title: "進んだ内容", items: summary.progress)
                    SummaryListSection(title: "現在の状態", items: summary.currentState)
                    SummaryListSection(title: "重要な判断", items: summary.decisions)
                    SummaryListSection(title: "問題・確認待ち", items: summary.blockers)
                    SummaryListSection(title: "次の予定", items: summary.nextSteps)

                    if !summary.sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("セッション別").font(.headline)
                            ForEach(summary.sessions) { session in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(session.source) — \(session.sessionID)")
                                        .font(.subheadline.bold())
                                    Text(session.summary)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(12)
                                .background(BrandPalette.bone, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                } else if entry.status == .pending {
                    ContentUnavailableView {
                        Label("要約できませんでした", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(entry.errorMessage ?? "要約CLIを確認して再試行してください。")
                    } actions: {
                        Button("再要約") { retry() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView("対象セッションなし", systemImage: "tray")
                }

                if !entry.collectionIssues.isEmpty {
                    SummaryListSection(
                        title: "収集時の注意",
                        items: entry.collectionIssues.map { "\($0.provider.displayName): \($0.message)" }
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("詳細")
    }
}

private struct SummaryListSection: View {
    let title: String
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(BrandPalette.petrolSlate)
                        Text(item).textSelection(.enabled)
                    }
                }
            }
        }
    }
}
