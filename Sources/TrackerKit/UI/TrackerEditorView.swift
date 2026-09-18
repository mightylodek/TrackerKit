import SwiftUI

/// Create or edit a tracker and its goal.
///
/// Editing a goal here does **not** overwrite the old one — it writes a new
/// version effective today. The sheet says so out loud, because a user who thinks
/// they're correcting a typo and is actually splitting their history deserves to
/// know which one is happening.
public struct TrackerEditorView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    private let existing: Tracker?

    @State private var title: String
    @State private var detail: String
    @State private var symbolName: String
    @State private var colorHex: String
    @State private var kind: TrackerKind

    @State private var hasGoal: Bool
    @State private var target: Double
    @State private var cadence: Cadence
    @State private var direction: GoalDirection
    @State private var unit: String
    @State private var goalNote: String
    @State private var effectiveFrom: Date

    @State private var showDeleteConfirmation = false

    public init(store: TrackerStore, tracker: Tracker?) {
        self.store = store
        self.existing = tracker

        let palette = ChartPalette.standard
        let goal = tracker?.currentGoal

        _title = State(initialValue: tracker?.title ?? "")
        _detail = State(initialValue: tracker?.detail ?? "")
        _symbolName = State(initialValue: tracker?.symbolName ?? "target")
        _colorHex = State(initialValue: tracker?.colorHex ?? palette.seriesHex(store.trackers.count))
        _kind = State(initialValue: tracker?.kind ?? .checkbox)

        _hasGoal = State(initialValue: goal != nil)
        _target = State(initialValue: goal?.target ?? 1)
        _cadence = State(initialValue: goal?.cadence ?? .daily)
        _direction = State(initialValue: goal?.direction ?? .atLeast)
        _unit = State(initialValue: goal?.unit ?? (tracker?.kind ?? .checkbox).defaultUnit)
        _goalNote = State(initialValue: "")
        _effectiveFrom = State(initialValue: .now)
    }

    private var isNew: Bool { existing == nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when saving would create a new goal version rather than set the first one.
    private var goalIsChanging: Bool {
        guard let current = existing?.currentGoal, hasGoal else { return false }
        return current.target != target
            || current.cadence != cadence
            || current.direction != direction
            || current.unit != unit
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("What are you tracking?") {
                    TextField("Name", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Notes (optional)", text: $detail, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(TrackerKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    .onChange(of: kind) { _, newValue in
                        if unit.isEmpty || TrackerKind.allCases.contains(where: { $0.defaultUnit == unit }) {
                            unit = newValue.defaultUnit
                        }
                    }
                } footer: {
                    Text(kindExplanation)
                }

                Section("Look") {
                    ColorSwatchPicker(selection: $colorHex)
                    SymbolPicker(selection: $symbolName, symbols: Self.trackerSymbols)
                }

                goalSection

                if let existing, !isNew {
                    Section {
                        Button(existing.isArchived ? "Unarchive" : "Archive") {
                            store.setArchived(!existing.isArchived, trackerID: existing.id)
                            dismiss()
                        }
                        Button("Delete tracker", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } footer: {
                        Text("Archiving keeps every entry and hides the tracker from the dashboard. Deleting removes the history too.")
                    }
                }
            }
            .navigationTitle(isNew ? "New tracker" : "Edit tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete \(existing?.title ?? "tracker")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let existing { store.deleteTracker(existing.id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every entry and goal version is removed with it.")
            }
        }
    }

    // MARK: Goal

    @ViewBuilder
    private var goalSection: some View {
        Section {
            Toggle("Set a goal", isOn: $hasGoal.animation())

            if hasGoal {
                Picker("Direction", selection: $direction) {
                    ForEach(GoalDirection.allCases, id: \.self) { option in
                        Label(option.displayName, systemImage: option.symbolName).tag(option)
                    }
                }

                HStack {
                    Text("Target")
                    Spacer()
                    TextField("0", value: $target, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    TextField("unit", text: $unit)
                        .multilineTextAlignment(.leading)
                        .frame(width: 66)
                        .foregroundStyle(theme.textSecondary)
                }

                Picker("Per", selection: $cadence) {
                    ForEach(Cadence.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                if goalIsChanging {
                    DatePicker(
                        "In effect from",
                        selection: $effectiveFrom,
                        displayedComponents: .date
                    )
                    TextField("Why the change? (optional)", text: $goalNote)
                }
            }
        } header: {
            Text("Goal")
        } footer: {
            if goalIsChanging {
                Label {
                    Text("This adds a new goal version from \(effectiveFrom.formatted(date: .abbreviated, time: .omitted)). Your old target stays on the record, so past weeks are still scored against what you were actually aiming for.")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .foregroundStyle(theme.statusColor(.yellow))
            } else if hasGoal {
                Text(goalPreview)
            } else {
                Text("Without a goal this is a plain log — still charted, never stoplit.")
            }
        }
    }

    private var goalPreview: String {
        let summary = GoalVersion(
            target: target, cadence: cadence, direction: direction, unit: unit
        ).summary
        return "Reads as: \(summary)"
    }

    private var kindExplanation: String {
        switch kind {
        case .checkbox: "One tap a day. Did it or didn't."
        case .count: "Adds up through the day — reps, glasses, pages."
        case .duration: "Minutes, totalled per period."
        case .amount: "Any number with a unit — miles, pounds, dollars."
        case .rating: "A 1–5 score; the day's last entry wins."
        }
    }

    // MARK: Save

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let goal = hasGoal
            ? GoalVersion(
                effectiveFrom: goalIsChanging ? effectiveFrom : .now,
                target: target,
                cadence: cadence,
                direction: direction,
                unit: unit,
                aggregation: kind.defaultAggregation,
                note: goalNote.isEmpty ? nil : goalNote
              )
            : nil

        if var tracker = existing {
            tracker.title = trimmed
            tracker.detail = detail
            tracker.symbolName = symbolName
            tracker.colorHex = colorHex
            tracker.kind = kind
            store.update(tracker)

            if let goal, goalIsChanging || tracker.goalHistory.isEmpty {
                store.setGoal(goal, on: tracker.id)
            }
        } else {
            store.addTracker(
                title: trimmed,
                kind: kind,
                detail: detail,
                symbolName: symbolName,
                colorHex: colorHex,
                goal: goal
            )
        }
        dismiss()
    }

    static let trackerSymbols = [
        "target", "figure.run", "brain.head.profile", "drop.fill", "book.fill",
        "bed.double.fill", "fork.knife", "dumbbell.fill", "figure.basketball",
        "figure.soccer", "music.note", "pencil", "shoeprints.fill", "iphone",
        "face.smiling", "heart.fill", "sunrise.fill", "moon.fill",
        "checkmark.seal.fill", "flame.fill", "leaf.fill", "bolt.fill"
    ]
}

#Preview("Tracker editor") {
    let store = TrackerStore.preview()
    return TrackerEditorView(store: store, tracker: store.activeTrackers.first)
}
