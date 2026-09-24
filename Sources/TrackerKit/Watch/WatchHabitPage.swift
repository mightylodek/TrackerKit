// watchOS-only. See rule 17 in CLAUDE.md.
#if os(watchOS)

import SwiftUI

// MARK: - WatchHabitPage

/// One habit, filling the screen.
///
/// Top to bottom: the week as bars, then the quick-add, then the report. Tapping
/// the chart opens precise entry for anything the one-tap button can't say.
///
/// There is no list and no navigation stack here on purpose — a habit *is* a
/// page, and the swipe between them is the only navigation the wrist wants.
public struct WatchHabitPage: View {
    @Environment(\.trackerTheme) private var theme

    private let tracker: Tracker
    private let store: TrackerStore
    private let onPrint: () -> Void

    @State private var isLogging = false
    @State private var justLogged = false

    public init(tracker: Tracker, store: TrackerStore, onPrint: @escaping () -> Void) {
        self.tracker = tracker
        self.store = store
        self.onPrint = onPrint
    }

    private var progress: ProgressSnapshot? { store.currentProgress(for: tracker.id) }
    private var week: [DailyValue] { store.dailyValues(for: tracker.id, dayCount: 7) }

    private var total: Double { week.reduce(0) { $0 + $1.value } }
    private var unit: String { tracker.currentGoal?.unit ?? tracker.kind.defaultUnit }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                heading

                Button {
                    isLogging = true
                } label: {
                    WatchHabitChart(
                        values: week,
                        target: tracker.currentGoal?.target,
                        unit: unit,
                        colorHex: tracker.colorHex
                    )
                    .frame(height: 70)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tracker.title) this week. Tap to log an exact amount.")

                quickAdd
                reportButton
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(tracker.title)
        .sheet(isPresented: $isLogging) {
            WatchLogView(tracker: tracker, store: store)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatters.value(total, unit: unit))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
        .animation(theme.motion.snappyAnimation, value: total)
    }

    private var subtitle: String {
        guard let progress, let target = progress.target, target > 0 else { return "this week" }
        return "this week · goal \(Formatters.value(target, unit: unit))"
    }

    /// The one-tap log. Its label is the habit's own step, so it reads
    /// "Add 10 min" for Reading and "Add 1 glass" for Water.
    private var quickAdd: some View {
        Button {
            _ = store.log(trackerID: tracker.id)
            justLogged = true
        } label: {
            Label(
                tracker.kind == .checkbox
                    ? "Mark done"
                    : "Add \(Formatters.value(tracker.quickLogStep, unit: unit))",
                systemImage: "plus.circle.fill"
            )
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.identityColor(hex: tracker.colorHex))
        .sensoryFeedback(.increase, trigger: justLogged)
        .accessibilityIdentifier("watch.quickAdd")
    }

    private var reportButton: some View {
        Button(action: onPrint) {
            Label("Print report", systemImage: "doc.text")
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(theme.textSecondary)
        .accessibilityIdentifier("watch.printReport")
    }
}

#endif
