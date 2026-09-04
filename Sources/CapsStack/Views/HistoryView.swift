import AppKit
import CapsStackLocalization
import UniformTypeIdentifiers
import SwiftUI

enum HistoryExportNaming {
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "CapsStack-\(formatter.string(from: date)).md"
    }
}

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
                        canRetry: canRetry(entry),
                        copy: { copy(entry) },
                        export: { export(entry) },
                        delete: { entryPendingDeletion = entry }
                    )
                    ReturnBriefView(
                        entry: entry,
                        submitFeedback: controller.isTelemetryEnabled
                            ? { reason in controller.recordBriefFeedback(reason, for: entry) }
                            : nil
                    )
                } else {
                    ContentUnavailableView(
                        CapsStackText.resource(.noHistoryYet),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(CapsStackText.resource(.startRecordingAway))
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
        .navigationTitle(CapsStackText.resource(.history))
        .confirmationDialog(
            CapsStackText.resource(.deleteSelectedHistory),
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(CapsStackText.resource(.delete), role: .destructive) {
                if let entry = entryPendingDeletion {
                    controller.delete(entry)
                }
                entryPendingDeletion = nil
            }
            Button(CapsStackText.resource(.cancel), role: .cancel) {
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
                selectNewestEntry(in: entries)
                return
            }
            if !entries.contains(where: { $0.id == selection }) {
                selectNewestEntry(in: entries)
            }
        }
        .onChange(of: selection) { _, _ in
            // A success/error message belongs to the action on the previously selected row.
            // Clear it when navigating so a newly selected entry never looks as if its copy or
            // export action already completed.
            exportMessage = nil
            if let selectedEntry {
                controller.recordHistoryAction(.viewed, for: selectedEntry)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(CapsStackText.resource(.history))
                .font(.system(size: 32, weight: .bold))

            if controller.isShowingDemoData {
                Text(CapsStackText.resource(.demoData))
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            SummaryMarkdown.document(for: entry),
            forType: .string
        )
        controller.recordHistoryAction(.copied, for: entry)
        exportMessage = CapsStackText.resolve(entry.summary == nil ? .historyStatusCopied : .copied)
    }

    private func export(_ entry: HistoryEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = HistoryExportNaming.fileName(for: entry.interval.start)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try SummaryMarkdown.document(for: entry)
                    .write(to: url, atomically: true, encoding: .utf8)
                controller.recordHistoryAction(.exported, for: entry)
                exportMessage = CapsStackText.resolve(entry.summary == nil ? .historyStatusSaved : .saved)
            } catch {
                exportMessage = CapsStackText.resolve(.couldNotSave)
            }
        }
    }

    private func canRetry(_ entry: HistoryEntry) -> Bool {
        controller.isCapsStackEnabled
            && controller.phase != .summarizing
            && controller.phase != .away
            && controller.phase != .disabled
            && entry.status == .pending
            && entry.pendingArtifactID != nil
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

    private func selectNewestEntry(in entries: [HistoryEntry]) {
        selection = entries.first?.id
        if let newest = entries.first {
            displayedMonth = Calendar.current.startOfMonth(for: newest.interval.end)
        }
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
                    Text(CapsStackText.format(.sessionsCount, bucket.sessionCount))
                        .font(.caption2.weight(.medium))
                    Text(Self.durationText(for: bucket.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 116, height: 148, alignment: .topLeading)
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
    let canRetry: Bool
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
                Label(
                    CapsStackText.resource(entry.summary == nil ? .copyStatus : .copy),
                    systemImage: "doc.on.doc"
                )
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button(CapsStackText.resource(.exportMarkdown), action: export)
                if entry.status == .pending {
                    Button(CapsStackText.resource(.retrySummary), action: retry)
                        .disabled(!canRetry)
                }
                Divider()
                Button(CapsStackText.resource(.delete), role: .destructive, action: delete)
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
            Label(CapsStackText.format(.sessionsCount, entry.sessionCount), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(BrandPalette.BriefTheme.signal)
        case .pending:
            Label(CapsStackText.resource(.pendingSummary), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.orange)
        case .empty:
            Label(CapsStackText.resource(.noSessions), systemImage: "tray")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReturnBriefView: View {
    let entry: HistoryEntry
    let submitFeedback: ((TelemetryFeedbackReason) -> Bool)?
    @State private var showsCollectionNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 12) {
                Text(CapsStackText.resource(.returnBrief))
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
                    title: CapsStackText.resolve(.progress),
                    symbolName: "scope",
                    items: summary.progress,
                    checklist: false
                )
                BriefSection(
                    title: CapsStackText.resolve(.decisions),
                    symbolName: "checkmark",
                    items: summary.decisions,
                    checklist: false
                )
                BriefSection(
                    title: CapsStackText.resolve(.nextSteps),
                    symbolName: "arrow.right",
                    items: summary.nextSteps,
                    checklist: true
                )

                if !summary.projects.isEmpty {
                    ProjectBriefsView(projects: summary.projects)
                } else if !summary.sessions.isEmpty {
                    LegacySessionBriefsView(sessions: summary.sessions)
                }

                if !summary.currentState.isEmpty || !summary.blockers.isEmpty {
                    supplementalSections(summary)
                }
            } else if entry.status == .pending {
                VStack(alignment: .leading, spacing: 10) {
                    Label(CapsStackText.resource(.summaryUnavailable), systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(entry.errorMessage ?? CapsStackText.resolve(.checkSummarizerTryAgain))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(BrandPalette.BriefTheme.signal)
                        .frame(width: 42, height: 42)
                        .background(
                            BrandPalette.BriefTheme.signal.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 11)
                        )

                    Text(CapsStackText.resource(.noSourceSessions))
                        .font(.title3.bold())
                    Text(CapsStackText.resource(.noSourceSessionsDescription))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandPalette.BriefTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 12))
            }

            if let memo = entry.quickMemo, !memo.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(CapsStackText.resource(.awayMemo), systemImage: "square.and.pencil")
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
                DisclosureGroup(isExpanded: $showsCollectionNotes) {
                    CompactList(
                        title: CapsStackText.resolve(.collectionNotesDetail),
                        items: entry.collectionIssues.map {
                            "\($0.provider.collectionDisplayName): \($0.message)"
                        }
                    )
                    .padding(.top, 12)
                } label: {
                    Label(
                        CapsStackText.format(.collectionNotesCount, entry.collectionIssues.count),
                        systemImage: "info.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .padding(14)
                .background(BrandPalette.BriefTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 10))
            }

            if entry.status == .completed, let submitFeedback {
                BriefFeedbackView(submit: submitFeedback)
                    .id(entry.id)
            }

            footer
        }
        .onChange(of: entry.id) { _, _ in
            showsCollectionNotes = false
        }
    }

    @ViewBuilder
    private func supplementalSections(_ summary: SummaryDocument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !summary.currentState.isEmpty {
                CompactList(title: CapsStackText.resolve(.currentState), items: summary.currentState)
            }
            if !summary.blockers.isEmpty {
                CompactList(title: CapsStackText.resolve(.blockers), items: summary.blockers)
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
            Text(CapsStackText.format(
                .created,
                entry.interval.end.formatted(.dateTime.year().month().day().hour().minute())
            ))
            Text("|").foregroundStyle(.tertiary)
            Text(CapsStackText.format(.modelMetadata, entry.provider?.displayName ?? CapsStackText.resolve(.notSet)))
            Text("|").foregroundStyle(.tertiary)
            Text(CapsStackText.format(.characters, characterCount))
            if entry.fallbackUsed {
                Text("|").foregroundStyle(.tertiary)
                Text(CapsStackText.resource(.fallbackUsed))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

private struct BriefFeedbackView: View {
    let submit: (TelemetryFeedbackReason) -> Bool

    @State private var submittedReason: TelemetryFeedbackReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if submittedReason == nil {
                Text(CapsStackText.resource(.briefFeedbackPrompt))
                    .font(.subheadline.weight(.semibold))

                Text(CapsStackText.resource(.briefFeedbackDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(TelemetryFeedbackReason.allCases, id: \.self) { reason in
                        Button(feedbackTitle(for: reason)) {
                            guard submittedReason == nil, submit(reason) else { return }
                            submittedReason = reason
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Label(CapsStackText.resource(.briefFeedbackThanks), systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandPalette.BriefTheme.signal)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandPalette.BriefTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func feedbackTitle(for reason: TelemetryFeedbackReason) -> String {
        switch reason {
        case .helpful:
            CapsStackText.resolve(.briefFeedbackHelpful)
        case .missingImportantContext:
            CapsStackText.resolve(.briefFeedbackMissingContext)
        case .tooVerbose:
            CapsStackText.resolve(.briefFeedbackTooVerbose)
        case .incorrectOrMisleading:
            CapsStackText.resolve(.briefFeedbackIncorrect)
        }
    }
}

private struct ProjectBriefsView: View {
    let projects: [ProjectSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(CapsStackText.resource(.byProject), systemImage: "folder")
                .font(.subheadline.weight(.bold))

            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(project.name)
                            .font(.headline)
                        Spacer()
                        Text(CapsStackText.format(.sessionsCount, project.sessions.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(project.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    ForEach(project.sessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.source)
                                .font(.caption.weight(.semibold))
                            Text(session.summary)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandPalette.BriefTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(CapsStackText.format(.projectSessionsAccessibility, project.name, project.sessions.count))
            }
        }
    }
}

private struct LegacySessionBriefsView: View {
    let sessions: [SessionSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(CapsStackText.resource(.bySession), systemImage: "terminal")
                .font(.subheadline.weight(.bold))
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.source).font(.caption.weight(.semibold))
                    Text(session.summary).font(.callout).textSelection(.enabled)
                }
            }
        }
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
