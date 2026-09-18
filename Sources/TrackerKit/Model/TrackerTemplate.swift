import Foundation

// MARK: - TrackerBlueprint

/// A tracker a template will create.
public struct TrackerBlueprint: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var symbolName: String
    public var kind: TrackerKind
    public var target: Double?
    public var cadence: Cadence
    public var direction: GoalDirection
    public var unit: String
    /// Overrides the goal-derived quick-log step where the template knows better.
    public var quickLogIncrement: Double?
    /// Whether it starts ticked. Templates suggest; they don't impose.
    public var isRecommended: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        symbolName: String,
        kind: TrackerKind,
        target: Double? = nil,
        cadence: Cadence = .daily,
        direction: GoalDirection = .atLeast,
        unit: String = "",
        quickLogIncrement: Double? = nil,
        isRecommended: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.kind = kind
        self.target = target
        self.cadence = cadence
        self.direction = direction
        self.unit = unit
        self.quickLogIncrement = quickLogIncrement
        self.isRecommended = isRecommended
    }

    /// "At least 4 / wk", or "No goal" — shown so a person can judge the
    /// suggestion before accepting it.
    public var goalSummary: String {
        guard let target else { return "No goal — just a log" }
        return GoalVersion(
            target: target, cadence: cadence, direction: direction, unit: unit
        ).summary
    }
}

// MARK: - TrackerTemplate

/// A starting point: some trackers, and a dashboard arranged to suit them.
///
/// A new profile otherwise lands on an empty screen and has to invent both what
/// to track and how to look at it, which is a lot to ask before anyone has seen
/// the thing work. Templates are **suggestions, not decisions** — every tracker
/// can be unticked, and everything stays editable afterwards.
public struct TrackerTemplate: Identifiable, Sendable, Hashable {

    /// One card the template puts on the dashboard.
    public struct LayoutSlot: Sendable, Hashable {
        public var kind: DashboardCard.Kind
        /// Binds a tracker-scoped card to a blueprint by title. If that tracker
        /// wasn't selected, the slot is dropped.
        public var trackerTitle: String?

        public init(_ kind: DashboardCard.Kind, tracker trackerTitle: String? = nil) {
            self.kind = kind
            self.trackerTitle = trackerTitle
        }
    }

    public let id: String
    public var name: String
    public var summary: String
    public var symbolName: String
    public var blueprints: [TrackerBlueprint]
    public var layout: [LayoutSlot]

    public init(
        id: String,
        name: String,
        summary: String,
        symbolName: String,
        blueprints: [TrackerBlueprint],
        layout: [LayoutSlot]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.blueprints = blueprints
        self.layout = layout
    }

    public var recommended: [TrackerBlueprint] { blueprints.filter(\.isRecommended) }

    // MARK: Built-ins

    public static let all: [TrackerTemplate] = [
        .youthSport, .dailyHabits, .fitness, .schoolNight, .blank
    ]

    /// For a kid on a shared device. Weekly practice volume, not daily guilt.
    public static let youthSport = TrackerTemplate(
        id: "youth-sport",
        name: "Youth sport",
        summary: "Practice, conditioning and rest for a young athlete.",
        symbolName: "figure.basketball",
        blueprints: [
            TrackerBlueprint(
                title: "Practice", detail: "Skills work outside team sessions",
                symbolName: "figure.basketball", kind: .duration,
                target: 150, cadence: .weekly, unit: "min", quickLogIncrement: 15
            ),
            TrackerBlueprint(
                title: "Conditioning", detail: "Running, lifting, anything that builds the engine",
                symbolName: "figure.run", kind: .count,
                target: 3, cadence: .weekly, unit: "sessions"
            ),
            TrackerBlueprint(
                title: "Water", symbolName: "drop.fill", kind: .count,
                target: 8, cadence: .daily, unit: "glasses"
            ),
            TrackerBlueprint(
                title: "Sleep", detail: "Hours, honestly",
                symbolName: "bed.double.fill", kind: .amount,
                target: 9, cadence: .daily, unit: "hours", quickLogIncrement: 1
            ),
            TrackerBlueprint(
                title: "Stretching", symbolName: "figure.cooldown", kind: .checkbox,
                target: 1, cadence: .daily, isRecommended: false
            )
        ],
        layout: [
            LayoutSlot(.hero),
            LayoutSlot(.stoplightRollup),
            LayoutSlot(.trackerList),
            LayoutSlot(.heatmap, tracker: "Practice")
        ]
    )

    public static let dailyHabits = TrackerTemplate(
        id: "daily-habits",
        name: "Daily habits",
        summary: "A handful of small things, done most days.",
        symbolName: "checkmark.circle",
        blueprints: [
            TrackerBlueprint(
                title: "Morning routine", detail: "Up and moving before the day starts",
                symbolName: "sunrise.fill", kind: .checkbox, target: 1, cadence: .daily
            ),
            TrackerBlueprint(
                title: "Reading", symbolName: "book.fill", kind: .duration,
                target: 150, cadence: .weekly, unit: "min", quickLogIncrement: 10
            ),
            TrackerBlueprint(
                title: "Water", symbolName: "drop.fill", kind: .count,
                target: 8, cadence: .daily, unit: "glasses"
            ),
            TrackerBlueprint(
                title: "Screen time", detail: "Kept under the limit",
                symbolName: "iphone", kind: .duration,
                target: 120, cadence: .daily, direction: .atMost, unit: "min",
                quickLogIncrement: 15
            ),
            TrackerBlueprint(
                title: "Mood", detail: "End-of-day check-in",
                symbolName: "face.smiling", kind: .rating,
                target: 4, cadence: .daily, unit: "/5", isRecommended: false
            )
        ],
        layout: [
            LayoutSlot(.hero),
            LayoutSlot(.stoplightRollup),
            LayoutSlot(.trackerList),
            LayoutSlot(.streak)
        ]
    )

    public static let fitness = TrackerTemplate(
        id: "fitness",
        name: "Fitness",
        summary: "Training volume, movement and recovery.",
        symbolName: "dumbbell.fill",
        blueprints: [
            TrackerBlueprint(
                title: "Workouts", symbolName: "dumbbell.fill", kind: .count,
                target: 4, cadence: .weekly, unit: "sessions"
            ),
            TrackerBlueprint(
                title: "Steps", symbolName: "shoeprints.fill", kind: .amount,
                target: 8000, cadence: .daily, unit: "steps", quickLogIncrement: 100
            ),
            TrackerBlueprint(
                title: "Water", symbolName: "drop.fill", kind: .count,
                target: 8, cadence: .daily, unit: "glasses"
            ),
            TrackerBlueprint(
                title: "Sleep", symbolName: "bed.double.fill", kind: .amount,
                target: 8, cadence: .daily, unit: "hours", quickLogIncrement: 1
            )
        ],
        layout: [
            LayoutSlot(.hero),
            LayoutSlot(.trackerList),
            LayoutSlot(.periodBars, tracker: "Workouts")
        ]
    )

    public static let schoolNight = TrackerTemplate(
        id: "school-night",
        name: "School nights",
        summary: "Homework, practice and a sensible bedtime.",
        symbolName: "backpack.fill",
        blueprints: [
            TrackerBlueprint(
                title: "Homework", symbolName: "pencil", kind: .duration,
                target: 45, cadence: .daily, unit: "min", quickLogIncrement: 15
            ),
            TrackerBlueprint(
                title: "Instrument practice", symbolName: "music.note", kind: .duration,
                target: 100, cadence: .weekly, unit: "min", quickLogIncrement: 10
            ),
            TrackerBlueprint(
                title: "Reading", symbolName: "book.fill", kind: .duration,
                target: 20, cadence: .daily, unit: "min", quickLogIncrement: 10
            ),
            TrackerBlueprint(
                title: "Lights out on time", symbolName: "moon.fill", kind: .checkbox,
                target: 1, cadence: .daily
            )
        ],
        layout: [
            LayoutSlot(.hero),
            LayoutSlot(.trackerList),
            LayoutSlot(.heatmap, tracker: "Reading")
        ]
    )

    /// No trackers. Some people know exactly what they want.
    public static let blank = TrackerTemplate(
        id: "blank",
        name: "Start from scratch",
        summary: "No trackers. Add your own.",
        symbolName: "square.dashed",
        blueprints: [],
        layout: [LayoutSlot(.hero), LayoutSlot(.stoplightRollup), LayoutSlot(.trackerList)]
    )
}
