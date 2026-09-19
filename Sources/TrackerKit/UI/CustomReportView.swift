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
                    ForEach(report.trackers) { tracker in
                        trackerCard(tracker)
                    }
                }
            }
            .padding(theme.spacing.screenMargin)
        }
        .background(theme.plane)
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
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

    private func trackerCard(_ tracker: CustomReportTracker) -> some View {
        TrackerCard(title: tracker.title, subtitle: tracker.totalText) {
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                ForEach(tracker.sections) { section in
                    breakdownBlock(section, unit: tracker.unit)
                }
            }
        }
    }

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
                        .font(theme.typography.heading)
                        .foregroundStyle(theme.textPrimary)
                        .monospacedDigit()
                }
            } else {
                Text(section.breakdown.displayName)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)

                VStack(spacing: 0) {
                    ForEach(Array(section.buckets.enumerated()), id: \.element.id) { index, bucket in
                        if index > 0 {
                            Divider().overlay(theme.border)
                        }
                        bucketRow(bucket, unit: unit)
                    }
                }
            }
        }
    }

    private func bucketRow(_ bucket: ReportBucket, unit: String) -> some View {
        HStack {
            Text(bucket.label)
                .font(theme.typography.body)
                .foregroundStyle(bucket.isEmpty ? theme.textSecondary : theme.textPrimary)
            Spacer()
            // "Nothing logged" rather than a zero: a habit you can legitimately
            // do none of on purpose reads very differently from one you forgot.
            Text(bucket.isEmpty ? "—" : Formatters.value(bucket.value, unit: unit))
                .font(theme.typography.body)
                .foregroundStyle(bucket.isEmpty ? theme.textMuted : theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, theme.spacing.xs)
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
