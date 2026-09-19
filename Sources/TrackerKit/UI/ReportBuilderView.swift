// iOS-only. See rule 17 in CLAUDE.md.
#if os(iOS)

import SwiftUI

// MARK: - ReportBuilderView

/// Builds or edits a custom report.
///
/// The four choices are deliberately separate controls because they are separate
/// questions, and conflating them is how reporting UIs get confusing: *which*
/// habits, over *what* span, counting *which* days, grouped *how*.
public struct ReportBuilderView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    private let existing: ReportDefinition?

    @State private var name: String
    @State private var selected: Set<UUID>
    @State private var rangeKind: RangeKind
    @State private var absoluteStart: Date
    @State private var absoluteEnd: Date
    @State private var relativeDays: Int
    @State private var weekCount: Int
    @State private var weekdays: Set<Int>
    @State private var firstWeekday: Int
    @State private var breakdowns: Set<ReportBreakdown>

    @State private var isScheduled: Bool
    @State private var frequency: ReportFrequency
    @State private var scheduleTime: Date
    @State private var scheduleWeekday: Int

    /// The range *shape*, kept separate from its values so switching between
    /// kinds doesn't discard what was typed into the other one.
    private enum RangeKind: String, CaseIterable, Identifiable {
        case lastDays, lastWeeks, absolute, monthToDate, yearToDate
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .lastDays: "Recent days"
            case .lastWeeks: "Whole weeks"
            case .absolute: "Set dates"
            case .monthToDate: "This month"
            case .yearToDate: "This year"
            }
        }
    }

    public init(store: TrackerStore, definition: ReportDefinition? = nil) {
        self.store = store
        self.existing = definition

        let now = Date.now
        _name = State(initialValue: definition?.name ?? "")
        _selected = State(initialValue: Set(definition?.trackerIDs ?? []))
        _weekdays = State(initialValue: definition?.weekdays ?? [])
        _firstWeekday = State(initialValue: definition?.firstWeekday ?? 1)
        _breakdowns = State(initialValue: definition?.breakdowns ?? [.daily, .total])

        switch definition?.range {
        case .absolute(let start, let end):
            _rangeKind = State(initialValue: .absolute)
            _absoluteStart = State(initialValue: start)
            _absoluteEnd = State(initialValue: end)
            _relativeDays = State(initialValue: 7)
            _weekCount = State(initialValue: 1)
        case .lastDays(let days):
            _rangeKind = State(initialValue: .lastDays)
            _relativeDays = State(initialValue: days)
            _absoluteStart = State(initialValue: now)
            _absoluteEnd = State(initialValue: now)
            _weekCount = State(initialValue: 1)
        case .lastCompleteWeeks(let count):
            _rangeKind = State(initialValue: .lastWeeks)
            _weekCount = State(initialValue: count)
            _relativeDays = State(initialValue: 7)
            _absoluteStart = State(initialValue: now)
            _absoluteEnd = State(initialValue: now)
        case .monthToDate:
            _rangeKind = State(initialValue: .monthToDate)
            _relativeDays = State(initialValue: 7); _weekCount = State(initialValue: 1)
            _absoluteStart = State(initialValue: now); _absoluteEnd = State(initialValue: now)
        case .yearToDate:
            _rangeKind = State(initialValue: .yearToDate)
            _relativeDays = State(initialValue: 7); _weekCount = State(initialValue: 1)
            _absoluteStart = State(initialValue: now); _absoluteEnd = State(initialValue: now)
        case nil:
            _rangeKind = State(initialValue: .lastDays)
            _relativeDays = State(initialValue: 7); _weekCount = State(initialValue: 1)
            _absoluteStart = State(initialValue: now.addingTimeInterval(-6 * 86_400))
            _absoluteEnd = State(initialValue: now)
        }

        let schedule = definition?.scheduleID.flatMap { id in
            store.schedules.first { $0.id == id }
        }
        _isScheduled = State(initialValue: schedule?.isEnabled ?? false)
        _frequency = State(initialValue: schedule?.frequency ?? .weekly)
        _scheduleWeekday = State(initialValue: schedule?.weekday ?? 1)
        var components = DateComponents()
        components.hour = schedule?.hour ?? 18
        components.minute = schedule?.minute ?? 0
        _scheduleTime = State(initialValue: Calendar.current.date(from: components) ?? now)
    }

    public var body: some View {
        NavigationStack {
            Form {
                nameSection
                habitsSection
                rangeSection
                weekdaysSection
                totalsSection
                scheduleSection
                previewSection
            }
            .navigationTitle(existing == nil ? "New report" : "Edit report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("report.save")
                }
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Report name", text: $name)
                .accessibilityIdentifier("report.name")
        } footer: {
            Text("Something you'll recognise in a notification — \"Reading, Fri–Thu\".")
        }
    }

    private var habitsSection: some View {
        Section {
            if store.activeTrackers.isEmpty {
                Text("No habits to report on yet.")
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(store.activeTrackers) { tracker in
                Button {
                    toggle(tracker.id)
                } label: {
                    HStack(spacing: theme.spacing.md) {
                        Image(systemName: selected.contains(tracker.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(tracker.id) ? theme.accent : theme.textMuted)
                        Label(tracker.title, systemImage: tracker.symbolName)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report.habit.\(tracker.title)")
            }
        } header: {
            Text("Habits")
        } footer: {
            Text(selected.isEmpty ? "Pick at least one." : "\(selected.count) selected.")
        }
    }

    private var rangeSection: some View {
        Section {
            Picker("Range", selection: $rangeKind) {
                ForEach(RangeKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("report.rangeKind")

            switch rangeKind {
            case .lastDays:
                Stepper("Last \(relativeDays) day\(relativeDays == 1 ? "" : "s")",
                        value: $relativeDays, in: 1...365)
            case .lastWeeks:
                Stepper("Last \(weekCount) whole week\(weekCount == 1 ? "" : "s")",
                        value: $weekCount, in: 1...52)
                weekStartPicker
            case .absolute:
                DatePicker("From", selection: $absoluteStart, displayedComponents: .date)
                DatePicker("To", selection: $absoluteEnd, displayedComponents: .date)
            case .monthToDate, .yearToDate:
                EmptyView()
            }
        } header: {
            Text("Date range")
        } footer: {
            Text(rangeFooter)
        }
    }

    /// Shown wherever weeks actually matter — picking a start day for a report
    /// that never groups by week would be a control with no effect.
    @ViewBuilder
    private var weekStartPicker: some View {
        Picker("Weeks start on", selection: $firstWeekday) {
            ForEach(1...7, id: \.self) { day in
                Text(Calendar(identifier: .gregorian).weekdaySymbols[day - 1]).tag(day)
            }
        }
        .accessibilityIdentifier("report.weekStart")
    }

    private var weekdaysSection: some View {
        Section {
            HStack(spacing: theme.spacing.xs) {
                ForEach(1...7, id: \.self) { day in
                    weekdayChip(day)
                }
            }
            .frame(maxWidth: .infinity)

            if !weekdays.isEmpty {
                Button("Count every day") { weekdays = [] }
                    .foregroundStyle(theme.accent)
            }
        } header: {
            Text("Days that count")
        } footer: {
            Text(weekdays.isEmpty
                 ? "Every day is included."
                 : "Only these days are counted. Others are left out of the report entirely, not shown as zero.")
        }
    }

    private func weekdayChip(_ day: Int) -> some View {
        let symbols = Calendar(identifier: .gregorian).veryShortWeekdaySymbols
        let isOn = weekdays.contains(day)
        return Button {
            if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(symbols[day - 1])
                .font(theme.typography.label)
                .foregroundStyle(isOn ? theme.onAccent : theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: theme.metrics.minimumTouchTarget)
                .background {
                    Circle().fill(isOn ? theme.accent : theme.surface)
                }
                .overlay { Circle().strokeBorder(theme.border, lineWidth: isOn ? 0 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar(identifier: .gregorian).weekdaySymbols[day - 1])
        .accessibilityIdentifier("report.weekday.\(day)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var totalsSection: some View {
        Section {
            ForEach(ReportBreakdown.allCases, id: \.self) { breakdown in
                Toggle(breakdown.displayName, isOn: binding(for: breakdown))
                    .accessibilityIdentifier("report.breakdown.\(breakdown.rawValue)")
            }
            if breakdowns.contains(.weekly) && rangeKind != .lastWeeks {
                weekStartPicker
            }
        } header: {
            Text("Totals")
        } footer: {
            Text("Tick as many as you want — a report can show every day *and* a total.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Toggle("Remind me to send it", isOn: $isScheduled)
                .accessibilityIdentifier("report.scheduled")

            if isScheduled {
                Picker("How often", selection: $frequency) {
                    ForEach(ReportFrequency.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                if frequency.needsWeekday {
                    Picker("On", selection: $scheduleWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar(identifier: .gregorian).weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                }
                DatePicker("At", selection: $scheduleTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("The reminder opens this report with everything already filled in — habits, range and totals.")
        }
    }

    /// What it'll actually cover, before saving.
    @ViewBuilder
    private var previewSection: some View {
        if !selected.isEmpty {
            Section("Preview") {
                let report = store.buildReport(draft())
                LabeledContent("Covers", value: report.rangeText)
                ForEach(report.trackers) { tracker in
                    LabeledContent(tracker.title) {
                        Text(tracker.hasData ? tracker.totalText : "Nothing logged")
                            .foregroundStyle(tracker.hasData ? theme.textPrimary : theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Plumbing

    private var rangeFooter: String {
        switch rangeKind {
        case .lastDays: "Moves with the calendar, so a scheduled report always covers the most recent days."
        case .lastWeeks: "Whole weeks only — the week in progress is left out until it finishes."
        case .absolute: "Fixed dates. This report says the same thing whenever it runs."
        case .monthToDate: "From the 1st through today."
        case .yearToDate: "From January 1st through today."
        }
    }

    private func binding(for breakdown: ReportBreakdown) -> Binding<Bool> {
        Binding(
            get: { breakdowns.contains(breakdown) },
            set: { isOn in
                if isOn { breakdowns.insert(breakdown) } else { breakdowns.remove(breakdown) }
            }
        )
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private var canSave: Bool {
        !selected.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resolvedRange: ReportRange {
        switch rangeKind {
        case .lastDays: .lastDays(relativeDays)
        case .lastWeeks: .lastCompleteWeeks(weekCount)
        case .absolute: .absolute(start: absoluteStart, end: absoluteEnd)
        case .monthToDate: .monthToDate
        case .yearToDate: .yearToDate
        }
    }

    /// The definition as currently configured, for the preview and for saving.
    private func draft() -> ReportDefinition {
        ReportDefinition(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? "Untitled report" : name,
            profileID: store.activeProfileID ?? UUID(),
            // Sorted by the dashboard's order so the report reads predictably
            // rather than in whatever order the boxes were ticked.
            trackerIDs: store.activeTrackers.map(\.id).filter { selected.contains($0) },
            range: resolvedRange,
            weekdays: weekdays,
            firstWeekday: firstWeekday,
            breakdowns: breakdowns,
            scheduleID: existing?.scheduleID,
            createdAt: existing?.createdAt ?? .now
        )
    }

    private func save() {
        var definition = draft()
        definition.scheduleID = syncSchedule(for: definition)
        store.save(definition)
        dismiss()
    }

    /// Creates, updates or removes the schedule behind this report.
    private func syncSchedule(for definition: ReportDefinition) -> UUID? {
        let existingSchedule = definition.scheduleID.flatMap { id in
            store.schedules.first { $0.id == id }
        }

        guard isScheduled else {
            if let existingSchedule {
                // deleteSchedule cancels the pending notification itself.
                store.deleteSchedule(existingSchedule.id)
            }
            return nil
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
        var schedule = existingSchedule ?? ExportSchedule(profileID: definition.profileID)
        schedule.isEnabled = true
        schedule.frequency = frequency
        schedule.weekday = scheduleWeekday
        schedule.hour = components.hour ?? 18
        schedule.minute = components.minute ?? 0
        schedule.reportDefinitionID = definition.id

        if existingSchedule == nil {
            guard let created = store.addSchedule(schedule) else { return nil }
            schedule = created
        } else {
            store.update(schedule)
        }
        return schedule.id
    }
}

#endif
