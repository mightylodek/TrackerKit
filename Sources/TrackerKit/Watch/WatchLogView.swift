// watchOS-only. See rule 17 in CLAUDE.md.
#if os(watchOS)

import SwiftUI

// MARK: - WatchLogView

/// Logging an exact amount, driven by the Digital Crown.
///
/// The crown is the one input this device has that a phone doesn't, and typing
/// a number at 45mm is miserable — so the value is dialled, not typed. Steps are
/// the habit's own quick-log increment, so a reading session moves in tens of
/// minutes and water in single glasses.
public struct WatchLogView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let tracker: Tracker
    private let store: TrackerStore

    @State private var amount: Double

    public init(tracker: Tracker, store: TrackerStore) {
        self.tracker = tracker
        self.store = store
        _amount = State(initialValue: tracker.quickLogStep)
    }

    private var unit: String { tracker.currentGoal?.unit ?? tracker.kind.defaultUnit }
    private var step: Double { tracker.quickLogStep }

    /// A ceiling the crown can actually reach without spinning forever, while
    /// still allowing a genuinely big session.
    private var upperBound: Double {
        max(step * 20, (tracker.currentGoal?.target ?? step) * 3)
    }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            Text(Formatters.value(amount, unit: unit))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.identityColor(hex: tracker.colorHex))
                .monospacedDigit()
                .contentTransition(.numericText())
                .focusable()
                .digitalCrownRotation(
                    $amount,
                    from: step,
                    through: upperBound,
                    by: step,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .accessibilityIdentifier("watch.logAmount")

            Text("Turn the crown")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)

            Button("Log it") {
                _ = store.log(trackerID: tracker.id, value: amount)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.identityColor(hex: tracker.colorHex))
            .accessibilityIdentifier("watch.logConfirm")
        }
        .navigationTitle(tracker.title)
        .animation(theme.motion.snappyAnimation, value: amount)
    }
}

#endif
