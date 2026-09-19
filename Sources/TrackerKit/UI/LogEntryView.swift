// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// The logging sheet. Shape follows the tracker kind — a checkbox gets one big
/// button, a count gets a stepper with quick-add chips, a rating gets stars.
///
/// Backdating is first-class rather than hidden: people log yesterday constantly,
/// and an app that makes that hard gets bad data instead of no data.
public struct LogEntryView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let tracker: Tracker
    private let store: TrackerStore
    private let session: ProfileSession?

    @State private var value: Double
    @State private var date: Date
    @State private var note: String
    @State private var justLogged = false

    public init(tracker: Tracker, store: TrackerStore, session: ProfileSession? = nil, date: Date = .now) {
        self.tracker = tracker
        self.store = store
        self.session = session
        _value = State(initialValue: tracker.quickLogStep)
        _date = State(initialValue: date)
        _note = State(initialValue: "")
    }

    private var goal: GoalVersion? { tracker.goal(on: date) }
    private var unit: String { goal?.unit ?? tracker.kind.defaultUnit }

    private var snapshot: ProgressSnapshot? {
        store.currentProgress(for: tracker.id)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    inputControl
                    dateControl
                    noteField
                    logButton
                }
                .padding()
            }
            .background(theme.plane)
            .navigationTitle("Log \(tracker.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: tracker.symbolName)
                .font(.system(size: 34))
                .foregroundStyle(theme.identityColor(for: tracker))
                .frame(width: 72, height: 72)
                .background(Circle().fill(theme.identityColor(for: tracker).opacity(0.14)))

            if let snapshot, let target = snapshot.target {
                VStack(spacing: 6) {
                    Text(snapshot.progressTextWithTarget)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                        .pulse(on: snapshot.actual)

                    MiniProgressBar(
                        fraction: snapshot.fraction ?? 0,
                        status: snapshot.status,
                        color: theme.identityColor(for: tracker),
                        height: 8
                    )
                    .frame(maxWidth: 260)

                    Text(store.progress.stoplight.explanation(
                        status: snapshot.status,
                        actual: snapshot.actual,
                        target: target,
                        direction: snapshot.direction,
                        unit: snapshot.unit,
                        daysRemaining: store.calculator.daysRemaining(in: snapshot.period)
                    ))
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)
                }
            } else if let snapshot {
                Text(Formatters.value(snapshot.actual, unit: unit))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }

    // MARK: Input

    @ViewBuilder
    private var inputControl: some View {
        switch tracker.kind {
        case .checkbox:
            checkboxControl
        case .rating:
            ratingControl
        case .count, .duration, .amount:
            numericControl
        }
    }

    private var checkboxControl: some View {
        let isDone = store.entries(for: tracker.id)
            .contains { store.calculator.isSameDay($0.date, date) }

        return Button {
            store.toggle(trackerID: tracker.id, on: date)
            session?.touch()
            session?.publishWidgets()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 62))
                    .foregroundStyle(isDone ? theme.identityColor(for: tracker) : theme.axis)
                    .contentTransition(.symbolEffect(.replace))
                Text(isDone ? "Done for \(Formatters.friendlyDay(date).lowercased())" : "Tap to mark done")
                    .font(theme.typography.heading)
                    .foregroundStyle(isDone ? theme.textPrimary : theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(theme.surface, in: .rect(cornerRadius: theme.radii.card))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.card)
                    .strokeBorder(isDone ? theme.identityColor(for: tracker) : theme.border, lineWidth: isDone ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isDone)
    }

    private var ratingControl: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        value = Double(star)
                    } label: {
                        Image(systemName: Double(star) <= value ? "star.fill" : "star")
                            .font(.system(size: 34))
                            .foregroundStyle(Double(star) <= value ? theme.identityColor(for: tracker) : theme.axis)
                            .trackerTouchTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
            Text("\(Int(value)) out of 5")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: .rect(cornerRadius: theme.radii.card))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private var numericControl: some View {
        VStack(spacing: 16) {
            HStack(spacing: 22) {
                stepperButton(systemName: "minus", enabled: value > tracker.quickLogStep) {
                    value = max(tracker.quickLogStep, value - tracker.quickLogStep)
                }

                VStack(spacing: 0) {
                    Text(Formatters.number(value))
                        .font(theme.typography.displaySize(52))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                    if !unit.isEmpty {
                        Text(unit)
                            .font(theme.typography.subheadline)
                            .foregroundStyle(theme.textMuted)
                    }
                }
                .frame(minWidth: 130)

                stepperButton(systemName: "plus", enabled: true) {
                    value += tracker.quickLogStep
                }
            }

            // Quick chips for the amounts people actually log.
            FlowLayout(spacing: 8) {
                ForEach(quickValues, id: \.self) { quick in
                    Button {
                        value = quick
                    } label: {
                        Text(Formatters.number(quick))
                            .font(theme.typography.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(value == quick ? theme.surface : theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(value == quick ? theme.identityColor(for: tracker) : theme.plane)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: .rect(cornerRadius: theme.radii.card))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private func stepperButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(enabled ? theme.textPrimary : theme.textMuted)
                .frame(width: 54, height: 54)
                .background(Circle().fill(theme.plane))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Sensible quick values derived from the goal, not hardcoded.
    private var quickValues: [Double] {
        let step = tracker.quickLogStep
        guard let target = goal?.target, target > 0 else {
            return [step, step * 2, step * 5, step * 10]
        }
        switch tracker.kind {
        case .duration:
            return [15, 30, 45, 60, 90].filter { $0 <= max(target * 2, 90) }
        case .count:
            return [1, 2, 3, 5, 10].filter { $0 <= max(target, 10) }
        case .amount:
            return [step, step * 2, step * 5, step * 10].filter { $0 <= target * 1.5 }
        default:
            return [step]
        }
    }

    // MARK: Date and note

    private var dateControl: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { offset in
                    let day = store.calculator.calendar.date(
                        byAdding: .day, value: -offset, to: .now
                    ) ?? .now
                    let isSelected = store.calculator.isSameDay(day, date)

                    Button {
                        date = day
                    } label: {
                        Text(Formatters.friendlyDay(day))
                            .font(theme.typography.subheadline.weight(.medium))
                            .foregroundStyle(isSelected ? theme.surface : theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? theme.textPrimary : theme.plane)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            DatePicker("Other date", selection: $date, in: ...Date.now, displayedComponents: .date)
                .font(theme.typography.subheadline)
        }
    }

    private var noteField: some View {
        TextField("Note (optional)", text: $note, axis: .vertical)
            .lineLimit(1...3)
            .padding(12)
            .background(theme.surface, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border, lineWidth: 1)
            }
    }

    // MARK: Log

    @ViewBuilder
    private var logButton: some View {
        if tracker.kind != .checkbox {
            Button {
                store.log(
                    trackerID: tracker.id,
                    value: value,
                    date: date,
                    note: note.isEmpty ? nil : note
                )
                session?.touch()
                session?.publishWidgets()
                justLogged = true
                dismiss()
            } label: {
                Text("Log \(Formatters.value(value, unit: unit))")
                    .font(theme.typography.heading)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(theme.identityColor(for: tracker), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: justLogged)
        }
    }
}

// MARK: - Helpers

extension ProgressSnapshot {
    /// "42 / 60 min" — the progress string used across logging and detail screens.
    var progressTextWithTarget: String {
        guard let target else { return Formatters.value(actual, unit: unit) }
        return "\(Formatters.value(actual, unit: unit)) / \(Formatters.value(target, unit: unit))"
    }
}

#Preview("Log entry") {
    let store = TrackerStore.preview()
    let tracker = store.activeTrackers.first { $0.kind == .count } ?? store.activeTrackers[0]
    return LogEntryView(tracker: tracker, store: store)
}

#endif
