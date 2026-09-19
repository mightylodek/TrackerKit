// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// Every goal a tracker has ever had, newest first, with the stretch each one
/// governed and how the tracker actually performed under it.
///
/// This is the payoff for storing goals as versions instead of editing them in
/// place. "I was hitting 4 a week easily, so I moved it to 6 and fell apart" is a
/// real and common pattern, and it's invisible in any app that overwrites the
/// target.
public struct GoalHistoryView: View {
    @Environment(\.trackerTheme) private var theme

    private let tracker: Tracker
    private let store: TrackerStore

    @State private var expandedGoalID: UUID?

    public init(tracker: Tracker, store: TrackerStore) {
        self.tracker = tracker
        self.store = store
    }

    private var timeline: [(goal: GoalVersion, endedAt: Date?)] {
        tracker.goalTimeline.reversed()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if timeline.isEmpty {
                    ChartEmptyState(
                        message: "No goal has ever been set for this tracker.",
                        symbolName: "target"
                    )
                    .padding(.top, 60)
                } else {
                    summaryCard
                    ForEach(Array(timeline.enumerated()), id: \.element.goal.id) { index, entry in
                        goalCard(entry: entry, isCurrent: index == 0)
                            .staggeredAppear(index: index)
                    }
                }
            }
            .padding()
        }
        .background(theme.plane)
        .navigationTitle("Goal history")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Summary

    private var summaryCard: some View {
        TrackerCard(
            title: tracker.title,
            subtitle: "\(timeline.count) goal version\(timeline.count == 1 ? "" : "s") on record"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // The stepped target line across the whole history — the clearest
                // single picture of a moving goalpost.
                let history = store.history(for: tracker.id, periodCount: 26)
                if history.count > 1 {
                    TrackerPeriodBarChart(
                        snapshots: history,
                        colorByStatus: true,
                        seriesColorHex: tracker.colorHex,
                        height: 170
                    )
                }

                Label(
                    "The dashed line is the target that was actually in force at the time.",
                    systemImage: "info.circle"
                )
                .font(theme.typography.label)
                .foregroundStyle(theme.textMuted)
            }
        }
    }

    // MARK: Goal card

    private func goalCard(entry: (goal: GoalVersion, endedAt: Date?), isCurrent: Bool) -> some View {
        let goal = entry.goal
        let interval = DateInterval(
            start: goal.effectiveFrom,
            end: entry.endedAt ?? max(Date.now, goal.effectiveFrom.addingTimeInterval(1))
        )
        let performance = performance(for: goal, in: interval)

        return TrackerCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(goal.summary)
                                .font(theme.typography.heading)
                                .foregroundStyle(theme.textPrimary)

                            if isCurrent {
                                Text("CURRENT")
                                    .font(theme.typography.micro.weight(.heavy))
                                    .foregroundStyle(theme.surface)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(theme.identityColor(for: tracker)))
                            }
                        }

                        Text(dateRangeText(from: goal.effectiveFrom, to: entry.endedAt))
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer()

                    if let performance {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Formatters.percent(performance.hitRate))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                            Text("hit rate")
                                .font(theme.typography.micro)
                                .foregroundStyle(theme.textMuted)
                        }
                    }
                }

                if let note = goal.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(theme.typography.micro)
                            .foregroundStyle(theme.textMuted)
                        Text(note)
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                if let performance {
                    Divider().overlay(theme.gridline)

                    HStack(spacing: 20) {
                        statBlock(
                            value: "\(performance.metCount)/\(performance.totalPeriods)",
                            label: "periods met"
                        )
                        statBlock(
                            value: Formatters.value(performance.average, unit: goal.unit),
                            label: "average"
                        )
                        statBlock(
                            value: Formatters.value(performance.best, unit: goal.unit),
                            label: "best"
                        )
                    }

                    if !performance.snapshots.isEmpty {
                        SparklineView(
                            snapshots: performance.snapshots,
                            color: theme.identityColor(for: tracker),
                            style: .statusBars
                        )
                        .frame(height: 38)
                    }
                }
            }
        }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(theme.typography.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(theme.typography.micro)
                .foregroundStyle(theme.textMuted)
        }
    }

    // MARK: Performance under one goal

    private struct GoalPerformance {
        let snapshots: [ProgressSnapshot]
        let metCount: Int
        let totalPeriods: Int
        let average: Double
        let best: Double

        var hitRate: Double {
            totalPeriods > 0 ? Double(metCount) / Double(totalPeriods) : 0
        }
    }

    /// Scores only the periods that fall inside this goal's own window, so each
    /// card measures that goal against the time it was actually in force.
    private func performance(for goal: GoalVersion, in interval: DateInterval) -> GoalPerformance? {
        let entries = store.allEntries(for: tracker.id)
        guard !entries.isEmpty else { return nil }

        let calculator = store.calculator
        let periods = calculator.periods(for: goal.cadence, in: interval)
        guard !periods.isEmpty else { return nil }

        let engine = store.progress
        let snapshots = periods
            .prefix(60)
            .map { period in
                engine.snapshot(tracker: tracker, entries: entries, period: period, now: .now)
            }
            .filter { $0.entryCount > 0 || $0.isPeriodComplete }

        guard !snapshots.isEmpty else { return nil }

        let completed = snapshots.filter(\.isPeriodComplete)
        let values = snapshots.map(\.actual)

        return GoalPerformance(
            snapshots: snapshots,
            metCount: completed.filter(\.isMet).count,
            totalPeriods: max(completed.count, 1),
            average: values.reduce(0, +) / Double(values.count),
            best: values.max() ?? 0
        )
    }

    private func dateRangeText(from start: Date, to end: Date?) -> String {
        let startText = start.formatted(date: .abbreviated, time: .omitted)
        guard let end else { return "Since \(startText)" }
        let days = store.calculator.dayCount(from: start, to: end)
        return "\(startText) – \(end.formatted(date: .abbreviated, time: .omitted)) · \(days) days"
    }
}

#Preview("Goal history") {
    let store = TrackerStore.preview()
    let tracker = store.activeTrackers.first { $0.goalHistory.count > 1 } ?? store.activeTrackers[0]

    return NavigationStack {
        GoalHistoryView(tracker: tracker, store: store)
    }
}

#endif
