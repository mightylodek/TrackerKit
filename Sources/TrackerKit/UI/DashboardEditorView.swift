// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// Arrange the dashboard: reorder, remove, add.
public struct DashboardEditorView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    @State private var isAdding = false
    @State private var showResetConfirmation = false

    public init(store: TrackerStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.dashboardLayout) { card in
                        row(for: card)
                    }
                    .onMove { store.moveDashboardCards(from: $0, to: $1) }
                    .onDelete { offsets in
                        for index in offsets {
                            store.removeDashboardCard(id: store.dashboardLayout[index].id)
                        }
                    }
                } header: {
                    Text("On your dashboard")
                } footer: {
                    Text("Drag to reorder, swipe to remove. Everything in the gallery can be added here.")
                }

                Section {
                    Button("Add a card", systemImage: "plus") { isAdding = true }
                    Button("Reset to default", systemImage: "arrow.uturn.backward") {
                        showResetConfirmation = true
                    }
                    .foregroundStyle(theme.statusColor(.red))
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAdding) {
                DashboardCardPicker(store: store)
            }
            .confirmationDialog(
                "Reset the dashboard?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { store.resetDashboardLayout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Puts back the hero, the rollup and the tracker list. Your trackers and entries aren't touched.")
            }
        }
    }

    private func row(for card: DashboardCard) -> some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: card.kind.symbolName)
                .foregroundStyle(theme.accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(card.kind.displayName)
                    .font(theme.typography.heading)
                    .foregroundStyle(theme.textPrimary)

                if let id = card.trackerID, let tracker = store.tracker(id) {
                    Text(tracker.title)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                } else if card.kind.needsTracker {
                    // The tracker was deleted; the card is skipped when drawing,
                    // and saying so here beats a row that looks fine and isn't.
                    Label("Tracker no longer exists", systemImage: "exclamationmark.triangle.fill")
                        .font(theme.typography.label)
                        .foregroundStyle(theme.statusColor(.yellow))
                }
            }
        }
        .accessibilityIdentifier("layout.\(card.kind.rawValue)")
    }
}

// MARK: - DashboardCardPicker

/// Pick a visual to add, and which tracker it should show.
public struct DashboardCardPicker: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    @State private var pendingKind: DashboardCard.Kind?

    public init(store: TrackerStore) {
        self.store = store
    }

    private var kinds: [DashboardCard.Kind] {
        DashboardCard.addableKinds(given: store.dashboardLayout)
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(kinds, id: \.self) { kind in
                    Button {
                        if kind.needsTracker {
                            pendingKind = kind
                        } else {
                            store.addDashboardCard(DashboardCard(kind: kind))
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: theme.spacing.md) {
                            Image(systemName: kind.symbolName)
                                .foregroundStyle(theme.accent)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayName)
                                    .font(theme.typography.heading)
                                    .foregroundStyle(theme.textPrimary)
                                Text(kind.explanation)
                                    .font(theme.typography.label)
                                    .foregroundStyle(theme.textSecondary)
                            }

                            Spacer()

                            if kind.needsTracker {
                                Image(systemName: "chevron.right")
                                    .font(theme.typography.micro)
                                    .foregroundStyle(theme.textMuted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add.\(kind.rawValue)")
                }
            }
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $pendingKind) { kind in
                TrackerPickerView(store: store, kind: kind) { tracker in
                    store.addDashboardCard(DashboardCard(kind: kind, trackerID: tracker.id))
                    dismiss()
                }
            }
        }
    }
}

extension DashboardCard.Kind: Identifiable {
    public var id: String { rawValue }
}

// MARK: - TrackerPickerView

/// Chooses which tracker a card should show.
public struct TrackerPickerView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    private let kind: DashboardCard.Kind
    private let onPick: (Tracker) -> Void

    public init(
        store: TrackerStore,
        kind: DashboardCard.Kind,
        onPick: @escaping (Tracker) -> Void
    ) {
        self.store = store
        self.kind = kind
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            List(store.activeTrackers) { tracker in
                Button {
                    onPick(tracker)
                    dismiss()
                } label: {
                    Label {
                        Text(tracker.title)
                            .foregroundStyle(theme.textPrimary)
                    } icon: {
                        Image(systemName: tracker.symbolName)
                            .foregroundStyle(theme.identityColor(for: tracker))
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Which tracker?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#endif
