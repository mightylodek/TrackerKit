// iOS-only. See rule 17 in CLAUDE.md.
#if os(iOS)

import SwiftUI

// MARK: - CustomReportView

/// A built report, read top to bottom.
///
/// Sections run finest-first — days, then weeks, then the total — because that
/// is the order someone reads a report in: the detail, then what it came to.
public struct CustomReportView: View {
    @Environment(\.trackerTheme) private var theme

    private let report: CustomReport

    @State private var share: ShareItem?
    @State private var isChoosingAppearance = false

    public init(report: CustomReport) {
        self.report = report
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header

                if report.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing logged in this range", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Change the dates, or log something first.")
                    }
                    .padding(.top, theme.spacing.xl)
                } else {
                    if !report.definition.visuals.isEmpty {
                        ReportVisualsView(report: report)
                    }

                    ForEach(report.trackers) { tracker in
                        ReportTrackerTable(tracker: tracker)
                    }
                }
            }
            .padding(theme.spacing.screenMargin)
        }
        .background(theme.plane)
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isChoosingAppearance = true
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .disabled(report.isEmpty)
                .accessibilityIdentifier("report.exportPDF")
            }
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        // Asked rather than assumed: a dark page is right on screen and wrong on
        // paper, where it lays down a near-black ground across every sheet.
        .confirmationDialog(
            "Export as PDF",
            isPresented: $isChoosingAppearance,
            titleVisibility: .visible
        ) {
            ForEach(CustomReportPDFRenderer.Appearance.allCases, id: \.self) { appearance in
                Button(appearance.displayName) { exportPDF(appearance) }
                    .accessibilityIdentifier("report.export.\(appearance.rawValue)")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Printing the dark theme covers the page in ink.")
        }
    }

    /// A shared file, wrapped so `.sheet(item:)` can key off it.
    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private func exportPDF(_ appearance: CustomReportPDFRenderer.Appearance) {
        // Rendering is synchronous and on the main actor because ImageRenderer
        // is; a multi-page report is a fraction of a second at this size.
        guard let url = try? CustomReportPDFRenderer().write(
            report, appearance: appearance, appTheme: theme
        ) else { return }
        share = ShareItem(url: url)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(report.rangeText)
                .font(theme.typography.heading)
                .foregroundStyle(theme.textPrimary)

            Text(subtitle)
                .font(theme.typography.label)
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let days = report.definition.weekdaySummary { parts.append(days) }
        if report.definition.breakdowns.contains(.weekly) {
            parts.append("weeks from \(report.definition.weekStartName)")
        }
        parts.append("generated \(Formatters.dayMonth(report.generatedAt))")
        return parts.joined(separator: " · ")
    }

}

// MARK: - ReportTrackerTable

/// One habit's numbers. Shared by the screen and the PDF so a printed report is
/// the same report, not a second implementation that drifts.
struct ReportTrackerTable: View {
    @Environment(\.trackerTheme) private var theme

    let tracker: CustomReportTracker
    /// Print sizing: smaller type and tighter rows, so a week of days is a
    /// quarter of a page rather than half of one.
    var isCompact: Bool = false

    init(tracker: CustomReportTracker, isCompact: Bool = false) {
        self.tracker = tracker
        self.isCompact = isCompact
    }

    var body: some View {
        TrackerCard(title: tracker.title, subtitle: tracker.totalText) {
            VStack(alignment: .leading, spacing: isCompact ? theme.spacing.sm : theme.spacing.lg) {
                ForEach(tracker.sections) { section in
                    breakdownBlock(section, unit: tracker.unit)
                }
            }
        }
    }

    private var rowFont: Font { isCompact ? theme.typography.label : theme.typography.body }
    private var rowPadding: CGFloat { isCompact ? 1 : theme.spacing.xs }

    @ViewBuilder
    private func breakdownBlock(_ section: CustomReportSection, unit: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            // The total is a headline, not a table of one row.
            if section.breakdown == .total, let bucket = section.buckets.first {
                HStack {
                    Text("Total")
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(Formatters.value(bucket.value, unit: unit))
                        .font(isCompact ? theme.typography.subheadline : theme.typography.heading)
                        .foregroundStyle(theme.textPrimary)
                        .monospacedDigit()
                }
            } else {
                Text(section.breakdown.displayName)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)

                if isCompact && section.buckets.count > 4 {
                    // Two columns on paper. A week of days down one column is
                    // 272pt — taller than the tile meant to hold it — and the
                    // height grows with the range, so a single column can never
                    // be made to fit in general.
                    let split = (section.buckets.count + 1) / 2
                    HStack(alignment: .top, spacing: theme.spacing.md) {
                        bucketColumn(Array(section.buckets.prefix(split)), unit: unit)
                        bucketColumn(Array(section.buckets.dropFirst(split)), unit: unit)
                    }
                } else {
                    bucketColumn(section.buckets, unit: unit)
                }
            }
        }
    }

    /// Daily buckets shorten to "Sun 13" in a narrow column; anything coarser
    /// (a month, a year) is already short and keeps its own label.
    private func compactLabel(_ bucket: ReportBucket) -> String {
        let span = bucket.interval.duration
        guard span <= 60 * 60 * 36 else { return bucket.label }
        return Formatters.compactDay(bucket.interval.start)
    }

    private func bucketColumn(_ buckets: [ReportBucket], unit: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                if index > 0 {
                    Divider().overlay(theme.border)
                }
                bucketRow(bucket, unit: unit)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bucketRow(_ bucket: ReportBucket, unit: String) -> some View {
        HStack {
            Text(isCompact ? compactLabel(bucket) : bucket.label)
                .font(rowFont)
                .foregroundStyle(bucket.isEmpty ? theme.textSecondary : theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: theme.spacing.sm)
            // "Nothing logged" rather than a zero: a habit you can legitimately
            // do none of on purpose reads very differently from one you forgot.
            Text(bucket.isEmpty ? "—" : Formatters.value(bucket.value, unit: unit))
                .font(rowFont)
                .foregroundStyle(bucket.isEmpty ? theme.textMuted : theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, rowPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucket.label), \(bucket.isEmpty ? "nothing logged" : Formatters.value(bucket.value, unit: unit))")
    }
}

// MARK: - ReportListView

/// Saved reports, and the way to build another.
public struct ReportListView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore

    /// Which builder is open, if any. One piece of state, because two `.sheet`
    /// modifiers on a single view silently cancel each other out.
    private enum Builder: Identifiable {
        case create
        case edit(ReportDefinition)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let definition): definition.id.uuidString
            }
        }

        var definition: ReportDefinition? {
            switch self {
            case .create: nil
            case .edit(let definition): definition
            }
        }
    }

    @State private var builder: Builder?

    public init(store: TrackerStore) {
        self.store = store
    }

    public var body: some View {
        List {
            if store.reportDefinitions.isEmpty {
                ContentUnavailableView {
                    Label("No reports yet", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Build one to pull a few habits together over a range you choose.")
                } actions: {
                    Button("Build a report") { builder = .create }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .foregroundStyle(theme.onAccent)
                }
                .listRowBackground(Color.clear)
            }

            ForEach(store.reportDefinitions) { definition in
                NavigationLink {
                    CustomReportView(report: store.buildReport(definition))
                } label: {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text(definition.name)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.textPrimary)
                        Text(definition.summary)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .accessibilityIdentifier("report.row.\(definition.name)")
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        store.deleteReport(definition.id)
                    }
                    Button("Edit") { builder = .edit(definition) }
                        .tint(theme.accent)
                }
            }
        }
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    builder = .create
                } label: {
                    Label("New report", systemImage: "plus")
                }
                .accessibilityIdentifier("report.new")
            }
        }
        .sheet(item: $builder) { builder in
            ReportBuilderView(store: store, definition: builder.definition)
        }
    }
}

#endif
