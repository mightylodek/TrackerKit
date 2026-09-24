// watchOS-only. See rule 17 in CLAUDE.md.
#if os(watchOS)

import SwiftUI

// MARK: - WatchReportView

/// The report, built on the watch.
///
/// The engine is pure value-type code and runs here unchanged, so the watch can
/// assemble exactly the same numbers the printed page would carry: the last
/// seven days, the last thirty, and six months.
///
/// **It cannot yet send them anywhere.** watchOS has no mail composer, no share
/// sheet and no printer, and this app is standalone by design, so there is no
/// phone to hand a file to. Rather than show a button that quietly does nothing,
/// the numbers are shown on the wrist and the limitation is stated. See
/// `docs/WATCH.md` — CloudKit is the likely route, and the screen does not
/// change when it lands.
public struct WatchReportView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let tracker: Tracker
    private let store: TrackerStore

    public init(tracker: Tracker, store: TrackerStore) {
        self.tracker = tracker
        self.store = store
    }

    private var unit: String { tracker.currentGoal?.unit ?? tracker.kind.defaultUnit }

    /// The three spans the printed page carries, built with the same engine.
    private func total(days: Int) -> Double {
        let definition = ReportDefinition(
            name: tracker.title,
            profileID: tracker.profileID,
            trackerIDs: [tracker.id],
            range: .lastDays(days),
            breakdowns: [.total]
        )
        return store.buildReport(definition).trackers.first?.total ?? 0
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Totals") {
                    row("Last 7 days", total(days: 7))
                    row("Last 30 days", total(days: 30))
                    row("Last 6 months", total(days: 183))
                }

                Section("This week") {
                    ForEach(store.dailyValues(for: tracker.id, dayCount: 7)) { day in
                        HStack {
                            Text(Formatters.weekdayInitial(day.date))
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text(day.hasData ? Formatters.value(day.value, unit: unit) : "—")
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(day.hasData ? theme.textPrimary : theme.textMuted)
                        }
                    }
                }

                Section {
                    Text("Sending a report from the watch isn't wired up yet. The numbers are here so they're not stuck behind it.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .navigationTitle(tracker.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("watch.report")
    }

    private func row(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(Formatters.value(value, unit: unit))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
        }
    }
}

#endif
