import SwiftUI

/// The undo affordance: a pill that appears where you logged and expires on its own.
///
/// Placed once at the app shell so it covers every screen that can log, rather
/// than each screen growing its own.
public struct UndoBar: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store: TrackerStore
    @State private var expiry: Task<Void, Never>?

    public init(store: TrackerStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let action = store.lastAction {
                content(for: action)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .task(id: action.id) {
                        // Restart the countdown for each new action, so logging
                        // three times in a row leaves one offer, not three.
                        try? await Task.sleep(for: .seconds(LoggedAction.offerDuration))
                        guard !Task.isCancelled else { return }
                        store.clearLastAction()
                    }
            }
        }
        .animation(theme.motion.snappyAnimation, value: store.lastAction?.id)
    }

    private func content(for action: LoggedAction) -> some View {
        HStack(spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.summary)
                    .font(theme.typography.labelEmphasis)
                    .foregroundStyle(theme.textPrimary)
                Text(action.trackerTitle)
                    .font(theme.typography.micro)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: theme.spacing.sm)

            Button {
                store.undoLastAction()
            } label: {
                Text("Undo")
                    .font(theme.typography.labelEmphasis)
                    .foregroundStyle(theme.accent)
                    .trackerTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("undo.button")
        }
        .padding(.leading, theme.spacing.lg)
        .padding(.trailing, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xs)
        .trackerControlSurface(shape: theme.radii.actionShape)
        .padding(.horizontal, theme.spacing.screenMargin)
        // No identifier on the container: setting one here propagates to every
        // child and overwrites the button's own, which makes the Undo button
        // unaddressable.
        .accessibilityElement(children: .contain)
    }
}
