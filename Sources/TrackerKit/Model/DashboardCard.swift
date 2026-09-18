import Foundation

/// One block on the dashboard.
///
/// The dashboard used to be a fixed composition: hero, rollup, tracker list, in
/// that order, for everyone. The gallery showed a dozen other visuals with no
/// way to take any of them home, which made it a showroom rather than a
/// library.
///
/// A layout is now just an ordered array of these, stored per profile — so two
/// kids sharing an iPad can have genuinely different dashboards.
public struct DashboardCard: Identifiable, Codable, Hashable, Sendable {

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case hero
        case stoplightRollup
        case trackerList
        case heatmap
        case periodBars
        case areaChart
        case lineChart
        case rings
        case bullets
        case streak
        case replay
        case rhythm3D

        public var displayName: String {
            switch self {
            case .hero: "Hero"
            case .stoplightRollup: "Where everything stands"
            case .trackerList: "Tracker list"
            case .heatmap: "Consistency calendar"
            case .periodBars: "Goal history bars"
            case .areaChart: "Volume over time"
            case .lineChart: "Trend line"
            case .rings: "Activity rings"
            case .bullets: "All goals at once"
            case .streak: "Streak"
            case .replay: "Progress replay"
            case .rhythm3D: "Weekday rhythm"
            }
        }

        public var explanation: String {
            switch self {
            case .hero: "Greeting, streak and today's headline."
            case .stoplightRollup: "One bar showing how many goals are on track."
            case .trackerList: "Every tracker, with one-tap logging."
            case .heatmap: "One square per day. Gaps are the story."
            case .periodBars: "Each period against the goal in force at the time."
            case .areaChart: "How much accumulated, day by day."
            case .lineChart: "The level over time, with an average."
            case .rings: "Concentric rings for your top goals."
            case .bullets: "Every goal against its target, densely."
            case .streak: "The chain, and whether today is locked in."
            case .replay: "History drawing itself."
            case .rhythm3D: "Weekday against week, in three dimensions."
            }
        }

        public var symbolName: String {
            switch self {
            case .hero: "rectangle.topthird.inset.filled"
            case .stoplightRollup: "chart.bar.horizontal.page"
            case .trackerList: "list.bullet"
            case .heatmap: "square.grid.3x3.fill"
            case .periodBars: "chart.bar.fill"
            case .areaChart: "chart.line.uptrend.xyaxis"
            case .lineChart: "chart.xyaxis.line"
            case .rings: "circle.circle"
            case .bullets: "list.bullet.indent"
            case .streak: "flame.fill"
            case .replay: "play.circle.fill"
            case .rhythm3D: "cube.fill"
            }
        }

        /// Whether this card shows one tracker's data and therefore needs to
        /// know which.
        public var needsTracker: Bool {
            switch self {
            case .heatmap, .periodBars, .areaChart, .lineChart, .replay, .rhythm3D: true
            case .hero, .stoplightRollup, .trackerList, .rings, .bullets, .streak: false
            }
        }

        /// Only one of these makes sense on a dashboard.
        public var isSingleton: Bool {
            switch self {
            case .hero, .stoplightRollup, .trackerList, .rings, .bullets, .streak: true
            default: false
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Which tracker this card shows, when ``Kind/needsTracker`` is true.
    public var trackerID: UUID?
    /// Hero style, for `.hero` cards.
    public var heroStyle: HeroStyle?
    /// Days of history for time-ranged cards.
    public var dayCount: Int

    public init(
        id: UUID = UUID(),
        kind: Kind,
        trackerID: UUID? = nil,
        heroStyle: HeroStyle? = nil,
        dayCount: Int = 112
    ) {
        self.id = id
        self.kind = kind
        self.trackerID = trackerID
        self.heroStyle = heroStyle
        self.dayCount = dayCount
    }

    /// The composition everyone starts with — what the dashboard was before it
    /// became arrangeable.
    public static let defaultLayout: [DashboardCard] = [
        DashboardCard(kind: .hero, heroStyle: .rings),
        DashboardCard(kind: .stoplightRollup),
        DashboardCard(kind: .trackerList)
    ]

    /// Kinds that can still be added, given what's already on the dashboard.
    public static func addableKinds(given existing: [DashboardCard]) -> [Kind] {
        let used = Set(existing.filter { $0.kind.isSingleton }.map(\.kind))
        return Kind.allCases.filter { !($0.isSingleton && used.contains($0)) }
    }
}

// MARK: - HeroStyle persistence

extension HeroStyle: Codable {}
