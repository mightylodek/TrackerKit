// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// The undo affordance: a pill that appears where you logged and expires on its own.
///
/// Placed once at the app shell so it covers every screen that can log, rather
/// than each screen growing its own.
public extension View {
    /// Offers undo above this screen's bottom edge.
    ///
    /// A `safeAreaInset` rather than an overlay, and that distinction is the
    /// whole fix: an overlay with a hand-tuned bottom padding sat directly on
    /// top of the detail screen's Add button, so tapping three times to log a
    /// thirty-minute session was impossible — the first tap put a bar over the
    /// button.
    ///
    /// Place this **inside** any action-bar inset. Bottom insets anchor to the
    /// bottom edge and grow upward, so the action bar keeps its position and the
    /// undo bar appears above it. The button does not move under your finger
    /// mid-tap, which matters when the whole point is tapping repeatedly.
    func trackerUndoBar(store: TrackerStore) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            UndoBar(store: store)
        }
    }
}

public struct UndoBar: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store: TrackerStore
    @State private var expiry: Task<Void, Never>?

    public init(store: TrackerStore) {
        self.store = store
    }

    public var body: some View {
        Group {
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
        // Idle, this must be genuinely absent, not merely invisible. As a
        // zero-height container it still swallowed touches along the bottom of
        // the screen and made the row's quick-log button unhittable — the bug
        // this whole change was meant to fix, reintroduced one layer down.
        .allowsHitTesting(store.lastAction != nil)
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

#endif
