import Foundation

// MARK: - ReportVisual

/// A chart a report can carry.
///
/// Deliberately a smaller set than the gallery. The gallery's job is to show
/// what the library can draw; a report's job is to be read once, probably on
/// paper, by someone who wasn't there. A rotatable 3-D field is a fine showcase
/// and a poor page.
public enum ReportVisual: String, Codable, Sendable, CaseIterable, Hashable {
    case area
    case line
    case bars
    case heatmap
    case rings
    case bullets
    case sparkline

    public var displayName: String {
        switch self {
        case .area: "Area chart"
        case .line: "Line chart"
        case .bars: "Bar chart"
        case .heatmap: "Consistency calendar"
        case .rings: "Progress rings"
        case .bullets: "Goal bullets"
        case .sparkline: "Sparklines"
        }
    }

    public var explanation: String {
        switch self {
        case .area: "Volume over time, filled. Good for showing accumulation."
        case .line: "Movement over time. Good for comparing habits against each other."
        case .bars: "One bar per day. Good when each day stands alone."
        case .heatmap: "A calendar grid. Good for spotting the gaps."
        case .rings: "How close each habit came to its goal."
        case .bullets: "Actual against target, one row per habit."
        case .sparkline: "A small shape per habit, for a compact summary."
        }
    }

    public var symbolName: String {
        switch self {
        case .area: "chart.xyaxis.line"
        case .line: "chart.line.uptrend.xyaxis"
        case .bars: "chart.bar.fill"
        case .heatmap: "calendar"
        case .rings: "circle.circle"
        case .bullets: "target"
        case .sparkline: "waveform.path.ecg"
        }
    }

    /// Whether one chart holds every habit, or each habit gets its own.
    ///
    /// Decides layout and, more importantly, whether stacking is even honest:
    /// two habits in different units must never share an axis.
    public var combinesTrackers: Bool {
        switch self {
        case .line, .rings, .bullets, .sparkline: true
        case .area, .bars, .heatmap: false
        }
    }

    /// Whether this chart needs a goal to mean anything.
    public var requiresGoal: Bool {
        switch self {
        case .rings, .bullets: true
        default: false
        }
    }
}
