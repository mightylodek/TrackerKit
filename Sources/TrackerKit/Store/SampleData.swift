import Foundation

/// Deterministic sample data for previews, the demo app and tests.
///
/// Everything here is generated from a fixed seed, so the demo looks identical on
/// every launch. That matters more than it sounds: a screenshot, a preview and a
/// test all describe the same numbers, and "it looked different last time" never
/// becomes a debugging session.
public enum SampleData {

    // MARK: Deterministic randomness

    /// A small linear congruential generator. Not cryptographic, not trying to be —
    /// it just needs to be repeatable across launches and platforms.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x4d59_5df4_d0f3_3173 : seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var result = state
            result ^= result >> 33
            result = result &* 0xff51_afd7_ed55_8ccd
            result ^= result >> 33
            return result
        }
    }

    // MARK: Seeding

    /// Populates a store with three profiles, a spread of tracker kinds, ~120 days
    /// of history and a couple of goal changes so the history view has something
    /// real to show.
    @MainActor
    public static func seed(into store: TrackerStore, now: Date = .now) {
        // One save and one reload for the whole seed, not one per entry.
        store.performBatch {
            seedContents(into: store, now: now)
        }
    }

    @MainActor
    private static func seedContents(into store: TrackerStore, now: Date) {
        let calculator = store.calculator
        var generator = SeededGenerator(seed: 20_260_917)

        let blueprints = profileBlueprints()

        for (profileIndex, blueprint) in blueprints.enumerated() {
            let profile = store.addProfile(
                name: blueprint.name,
                colorHex: blueprint.colorHex,
                symbolName: blueprint.symbolName,
                role: profileIndex == 0 ? .owner : .member
            )

            // Login history: the first profile is a near-daily user, the others
            // spottier, so the streak visuals have range to show.
            let loginDensity = blueprint.loginDensity
            for offset in stride(from: blueprint.historyDays, through: 0, by: -1) {
                guard let day = calculator.calendar.date(
                    byAdding: .day, value: -offset, to: calculator.startOfDay(now)
                ) else { continue }
                // Always log the last few days so the current streak is alive.
                let isRecent = offset <= blueprint.currentStreak
                if isRecent || Double.random(in: 0...1, using: &generator) < loginDensity {
                    store.recordLogin(for: profile.id, on: day)
                }
            }

            for (trackerIndex, spec) in blueprint.trackers.enumerated() {
                guard let tracker = store.addTracker(
                    title: spec.title,
                    kind: spec.kind,
                    detail: spec.detail,
                    symbolName: spec.symbolName,
                    colorHex: ChartPalette.standard.seriesHex(trackerIndex),
                    goal: nil,
                    profileID: profile.id
                ) else { continue }

                if let increment = spec.quickLogIncrement {
                    var updated = tracker
                    updated.quickLogIncrement = increment
                    store.update(updated)
                }

                // Goal history: the original goal, then any later revisions.
                for revision in spec.goalRevisions {
                    guard let effective = calculator.calendar.date(
                        byAdding: .day, value: -revision.daysAgo, to: calculator.startOfDay(now)
                    ) else { continue }
                    store.setGoal(
                        GoalVersion(
                            effectiveFrom: effective,
                            target: revision.target,
                            cadence: spec.cadence,
                            direction: spec.direction,
                            unit: spec.unit,
                            aggregation: spec.kind.defaultAggregation,
                            note: revision.note
                        ),
                        on: tracker.id
                    )
                }

                seedEntries(
                    into: store,
                    tracker: tracker,
                    spec: spec,
                    historyDays: blueprint.historyDays,
                    now: now,
                    generator: &generator
                )
            }

            // One export schedule on the owner profile so Settings isn't empty.
            if profileIndex == 0 {
                store.addSchedule(
                    ExportSchedule(
                        profileID: profile.id,
                        weekday: 1,
                        hour: 18,
                        channel: .email,
                        format: .html,
                        recipients: [],
                        lookbackDays: 7
                    )
                )
            }
        }
    }

    @MainActor
    private static func seedEntries(
        into store: TrackerStore,
        tracker: Tracker,
        spec: TrackerSpec,
        historyDays: Int,
        now: Date,
        generator: inout SeededGenerator
    ) {
        let calculator = store.calculator

        for offset in stride(from: historyDays, through: 0, by: -1) {
            guard let day = calculator.calendar.date(
                byAdding: .day, value: -offset, to: calculator.startOfDay(now)
            ) else { continue }

            // Skip days entirely at the spec's miss rate.
            if Double.random(in: 0...1, using: &generator) < spec.missRate { continue }

            // A gentle improvement over time so trend lines actually trend.
            let progressRatio = 1.0 - (Double(offset) / Double(max(historyDays, 1)))
            let drift = 1.0 + (spec.improvement * (progressRatio - 0.5))

            switch spec.kind {
            case .checkbox:
                store.log(trackerID: tracker.id, value: 1, date: noon(day, calculator))

            case .rating:
                let base = spec.baseValue * drift
                let jitter = Double.random(in: -0.8...0.8, using: &generator)
                let value = min(5, max(1, (base + jitter).rounded()))
                store.log(trackerID: tracker.id, value: value, date: noon(day, calculator))

            case .count, .duration, .amount:
                // One to three entries a day for count-like trackers.
                let sessions = spec.entriesPerDay
                let total = spec.baseValue * drift
                    * Double.random(in: 0.65...1.35, using: &generator)
                let perSession = max(spec.minimumValue, total / Double(sessions))
                for session in 0..<sessions {
                    let hour = 8 + session * 4
                    guard let stamp = calculator.calendar.date(
                        bySettingHour: min(hour, 21), minute: 0, second: 0, of: day
                    ) else { continue }
                    let value = spec.roundsToWhole
                        ? perSession.rounded()
                        : (perSession * 10).rounded() / 10
                    store.log(trackerID: tracker.id, value: max(value, spec.minimumValue), date: stamp)
                }
            }
        }
    }

    private static func noon(_ day: Date, _ calculator: PeriodCalculator) -> Date {
        calculator.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: Blueprints

    struct GoalRevision {
        var daysAgo: Int
        var target: Double
        var note: String?
    }

    struct TrackerSpec {
        var title: String
        var detail: String = ""
        var symbolName: String
        var kind: TrackerKind
        var cadence: Cadence
        var direction: GoalDirection = .atLeast
        var unit: String
        var goalRevisions: [GoalRevision]
        /// Typical daily total before jitter.
        var baseValue: Double
        /// Share of days with no entry at all.
        var missRate: Double
        /// How much the value drifts across the window. 0.3 = ±15% end to end.
        var improvement: Double = 0.2
        var entriesPerDay: Int = 1
        var roundsToWhole: Bool = true
        var minimumValue: Double = 1
        /// Overrides the goal-derived quick-log step where the owner has a view.
        var quickLogIncrement: Double?
    }

    struct ProfileBlueprint {
        var name: String
        var colorHex: String
        var symbolName: String
        var historyDays: Int
        var loginDensity: Double
        var currentStreak: Int
        var trackers: [TrackerSpec]
    }

    static func profileBlueprints() -> [ProfileBlueprint] {
        let palette = ChartPalette.standard

        let fullSet: [TrackerSpec] = [
            TrackerSpec(
                title: "Morning Routine",
                detail: "Out of bed and moving before 7:30",
                symbolName: "sunrise.fill",
                kind: .checkbox,
                cadence: .daily,
                unit: "",
                goalRevisions: [GoalRevision(daysAgo: 120, target: 1)],
                baseValue: 1,
                missRate: 0.18
            ),
            TrackerSpec(
                title: "Focus Time",
                detail: "Deep work, phone in another room",
                symbolName: "brain.head.profile",
                kind: .duration,
                cadence: .daily,
                unit: "min",
                goalRevisions: [
                    GoalRevision(daysAgo: 120, target: 45, note: "Starting point"),
                    GoalRevision(daysAgo: 45, target: 60, note: "Raised after a month of hitting 45 easily")
                ],
                baseValue: 58,
                missRate: 0.22,
                improvement: 0.35,
                entriesPerDay: 2,
                minimumValue: 5
            ),
            TrackerSpec(
                title: "Workouts",
                detail: "Anything that raises the heart rate",
                symbolName: "figure.run",
                kind: .count,
                cadence: .weekly,
                unit: "sessions",
                goalRevisions: [
                    GoalRevision(daysAgo: 120, target: 3, note: "Three a week to start"),
                    GoalRevision(daysAgo: 60, target: 4, note: "Bumped to four")
                ],
                baseValue: 1,
                missRate: 0.55,
                improvement: 0.15
            ),
            TrackerSpec(
                title: "Water",
                detail: "Glasses through the day",
                symbolName: "drop.fill",
                kind: .count,
                cadence: .daily,
                unit: "glasses",
                goalRevisions: [GoalRevision(daysAgo: 120, target: 8)],
                baseValue: 7,
                missRate: 0.12,
                improvement: 0.25,
                entriesPerDay: 3
            ),
            TrackerSpec(
                title: "Screen Time",
                detail: "Kept under the daily limit",
                symbolName: "iphone",
                kind: .duration,
                cadence: .daily,
                direction: .atMost,
                unit: "min",
                goalRevisions: [
                    GoalRevision(daysAgo: 120, target: 150),
                    GoalRevision(daysAgo: 30, target: 120, note: "Tightened the limit")
                ],
                baseValue: 118,
                missRate: 0.08,
                improvement: -0.25,
                entriesPerDay: 2,
                minimumValue: 10
            ),
            TrackerSpec(
                title: "Mood",
                detail: "End-of-day check-in",
                symbolName: "face.smiling",
                kind: .rating,
                cadence: .daily,
                unit: "/5",
                goalRevisions: [GoalRevision(daysAgo: 120, target: 4)],
                baseValue: 3.8,
                missRate: 0.2,
                improvement: 0.2
            ),
            TrackerSpec(
                title: "Steps",
                detail: "",
                symbolName: "shoeprints.fill",
                kind: .amount,
                cadence: .daily,
                unit: "steps",
                goalRevisions: [GoalRevision(daysAgo: 120, target: 8000)],
                baseValue: 8200,
                missRate: 0.1,
                improvement: 0.2,
                minimumValue: 200,
                // A twelfth of 8,000 would snap to 500. A hundred is the unit
                // people actually think in for steps.
                quickLogIncrement: 100
            ),
            TrackerSpec(
                title: "Reading",
                detail: "Any book, anything counts",
                symbolName: "book.fill",
                kind: .duration,
                cadence: .weekly,
                unit: "min",
                goalRevisions: [GoalRevision(daysAgo: 120, target: 150)],
                baseValue: 28,
                missRate: 0.35,
                improvement: 0.3,
                minimumValue: 5,
                // Reading happens in ten-minute sittings, not five.
                quickLogIncrement: 10
            )
        ]

        return [
            ProfileBlueprint(
                name: "Alex",
                colorHex: palette.seriesHex(0),
                symbolName: "person.fill",
                historyDays: 120,
                loginDensity: 0.88,
                currentStreak: 12,
                trackers: fullSet
            ),
            ProfileBlueprint(
                name: "Jordan",
                colorHex: palette.seriesHex(1),
                symbolName: "person.fill",
                historyDays: 90,
                loginDensity: 0.62,
                currentStreak: 4,
                trackers: Array(fullSet.prefix(5))
            ),
            ProfileBlueprint(
                name: "Sam",
                colorHex: palette.seriesHex(2),
                symbolName: "person.fill",
                historyDays: 60,
                loginDensity: 0.45,
                currentStreak: 1,
                trackers: Array(fullSet.prefix(4))
            )
        ]
    }

    // MARK: Lightweight fixtures

    /// A single tracker with generated daily history — for chart previews that
    /// don't want a whole store behind them.
    public static func previewTracker(
        title: String = "Focus Time",
        kind: TrackerKind = .duration,
        cadence: Cadence = .daily,
        target: Double = 60,
        unit: String = "min"
    ) -> (tracker: Tracker, entries: [Entry]) {
        let profileID = UUID()
        let tracker = Tracker(
            profileID: profileID,
            title: title,
            symbolName: "brain.head.profile",
            colorHex: ChartPalette.standard.seriesHex(0),
            kind: kind,
            goalHistory: [
                GoalVersion(
                    effectiveFrom: Date.now.addingTimeInterval(-120 * 86_400),
                    target: target * 0.75,
                    cadence: cadence,
                    unit: unit,
                    note: "Starting point"
                ),
                GoalVersion(
                    effectiveFrom: Date.now.addingTimeInterval(-45 * 86_400),
                    target: target,
                    cadence: cadence,
                    unit: unit,
                    note: "Raised the bar"
                )
            ]
        )

        var generator = SeededGenerator(seed: 4242)
        let calendar = Calendar.current
        var entries: [Entry] = []

        for offset in stride(from: 119, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date.now) else { continue }
            if Double.random(in: 0...1, using: &generator) < 0.18 { continue }
            let ratio = 1.0 - (Double(offset) / 120.0)
            let value = target * (0.6 + 0.5 * ratio) * Double.random(in: 0.7...1.3, using: &generator)
            entries.append(
                Entry(
                    trackerID: tracker.id,
                    profileID: profileID,
                    date: day,
                    value: (value).rounded()
                )
            )
        }

        return (tracker, entries)
    }

    /// Several trackers sharing one profile — for stacked and multi-series previews.
    public static func previewSeries(count: Int = 4) -> [(tracker: Tracker, entries: [Entry])] {
        let titles = ["Focus Time", "Workouts", "Reading", "Water", "Steps", "Mood"]
        return (0..<count).map { index in
            previewTracker(
                title: titles[index % titles.count],
                kind: .count,
                target: Double(20 + index * 8),
                unit: ""
            )
        }
    }
}
