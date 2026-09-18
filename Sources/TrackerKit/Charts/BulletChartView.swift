import SwiftUI

/// Bullet chart — one measure against its target, with qualitative bands behind it.
///
/// Invented by Stephen Few as the honest replacement for a gauge: it says the same
/// thing in a fraction of the space, stacks cleanly in a list, and doesn't spend
/// pixels on a dial. Anatomy:
///
/// - **Bands** — background ranges (poor / okay / good), drawn in one recessive hue
///   stepped light to dark, never in traffic-light colors. Colored bands would
///   fight the status color that actually carries meaning.
/// - **Measure** — the thick bar: what actually happened.
/// - **Comparative marker** — the tick: the target.
/// - **Projection** — an optional lighter extension: where the current pace lands.
///
/// A row of these is the densest honest way to show a dozen goals at once.
public struct BulletChartView: View {
    @Environment(\.trackerTheme) private var theme
    @State private var animatedFraction: Double = 0

    private let title: String?
    private let actual: Double
    private let target: Double?
    private let projected: Double?
    private let unit: String
    private let status: StoplightStatus
    private let direction: GoalDirection
    private let barHeight: CGFloat
    private let showsValue: Bool
    private let bandCount: Int

    public init(
        title: String? = nil,
        actual: Double,
        target: Double?,
        projected: Double? = nil,
        unit: String = "",
        status: StoplightStatus = .neutral,
        direction: GoalDirection = .atLeast,
        barHeight: CGFloat = 14,
        showsValue: Bool = true,
        bandCount: Int = 3
    ) {
        self.title = title
        self.actual = actual
        self.target = target
        self.projected = projected
        self.unit = unit
        self.status = status
        self.direction = direction
        self.barHeight = barHeight
        self.showsValue = showsValue
        self.bandCount = max(2, min(bandCount, 4))
    }

    /// Builds a bullet straight from a scored period.
    public init(
        snapshot: ProgressSnapshot,
        title: String? = nil,
        projected: Double? = nil,
        barHeight: CGFloat = 14,
        showsValue: Bool = true
    ) {
        self.init(
            title: title,
            actual: snapshot.actual,
            target: snapshot.target,
            projected: projected,
            unit: snapshot.unit,
            status: snapshot.status,
            direction: snapshot.direction,
            barHeight: barHeight,
            showsValue: showsValue
        )
    }

    /// The axis maximum. Leaves headroom past the target so a bar that beats it
    /// still has somewhere to go.
    private var scaleMax: Double {
        let candidates = [actual, target ?? 0, projected ?? 0].filter(\.isFinite)
        let peak = candidates.max() ?? 1
        let base = max(peak, (target ?? peak) * 1.25)
        return base > 0 ? base : 1
    }

    private var measureColor: Color {
        status == .neutral ? theme.accent : theme.statusColor(status)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if title != nil || showsValue {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(theme.typography.subheadline.weight(.medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if showsValue {
                        Text(Formatters.value(actual, unit: unit))
                            .font(theme.typography.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                        if let target {
                            Text("/ \(Formatters.value(target, unit: unit))")
                                .font(theme.typography.label)
                                .monospacedDigit()
                                .foregroundStyle(theme.textMuted)
                        }
                    }
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    bands(width: width)
                    projectionBar(width: width)
                    measureBar(width: width)
                    targetMarker(width: width)
                }
                .frame(height: barHeight * 1.6, alignment: .center)
            }
            .frame(height: barHeight * 1.6)
        }
        .onAppear {
            guard theme.motion.animatesOnAppear else {
                animatedFraction = 1
                return
            }
            withAnimation(theme.motion.fillAnimation) { animatedFraction = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Layers

    /// Qualitative ranges in one recessive hue, light to dark.
    private func bands(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<bandCount, id: \.self) { index in
                Rectangle()
                    .fill(theme.gridline.opacity(0.35 + Double(index) * 0.22))
                    .frame(width: width / CGFloat(bandCount))
            }
        }
        .frame(height: barHeight * 1.6)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Where the current pace lands, drawn behind the real bar so it can never be
    /// mistaken for what actually happened.
    @ViewBuilder
    private func projectionBar(width: CGFloat) -> some View {
        if let projected, projected > actual {
            let fraction = min(projected / scaleMax, 1)
            RoundedRectangle(cornerRadius: theme.metrics.markCornerRadius)
                .fill(measureColor.opacity(0.22))
                .frame(width: max(2, width * fraction * animatedFraction), height: barHeight)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(measureColor.opacity(0.5))
                        .frame(width: 1.5, height: barHeight)
                }
        }
    }

    private func measureBar(width: CGFloat) -> some View {
        let fraction = min(max(actual / scaleMax, 0), 1)
        return UnevenRoundedRectangle(
            topLeadingRadius: 2,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: theme.metrics.markCornerRadius,
            topTrailingRadius: theme.metrics.markCornerRadius
        )
        .fill(measureColor)
        .frame(width: max(2, width * fraction * animatedFraction), height: barHeight)
    }

    /// The target tick, drawn as a full-height rule with a surface-colored halo so
    /// it stays visible when the bar runs past it.
    @ViewBuilder
    private func targetMarker(width: CGFloat) -> some View {
        if let target, target > 0 {
            let x = min(target / scaleMax, 1) * width
            Rectangle()
                .fill(theme.textPrimary)
                .frame(width: 2.5, height: barHeight * 1.5)
                .overlay {
                    Rectangle()
                        .strokeBorder(theme.surface, lineWidth: 1)
                }
                .offset(x: max(0, x - 1.25))
                .accessibilityHidden(true)
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let title { parts.append(title) }
        parts.append(Formatters.value(actual, unit: unit))
        if let target {
            parts.append("of \(Formatters.value(target, unit: unit)) \(direction.displayName.lowercased())")
        }
        if status != .neutral { parts.append(status.displayName) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - BulletChartList

/// A stack of bullets sharing one alignment — the dense "everything at once" view.
public struct BulletChartList: View {
    @Environment(\.trackerTheme) private var theme

    private let items: [(title: String, snapshot: ProgressSnapshot)]
    private let projections: [UUID: Double]

    public init(
        items: [(title: String, snapshot: ProgressSnapshot)],
        projections: [UUID: Double] = [:]
    ) {
        self.items = items
        self.projections = projections
    }

    /// Builds the list from trackers and their current snapshots.
    public init(trackers: [Tracker], snapshots: [ProgressSnapshot], showProjections: Bool = true) {
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.trackerID, $0) })
        self.items = trackers.compactMap { tracker in
            byID[tracker.id].map { (tracker.title, $0) }
        }

        if showProjections {
            let engine = TrendEngine()
            var projections: [UUID: Double] = [:]
            for snapshot in snapshots {
                if let projected = engine.projectedTotal(for: snapshot) {
                    projections[snapshot.trackerID] = projected
                }
            }
            self.projections = projections
        } else {
            self.projections = [:]
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if items.isEmpty {
                ChartEmptyState(message: "No goals to compare", symbolName: "list.bullet")
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    BulletChartView(
                        snapshot: item.snapshot,
                        title: item.title,
                        projected: projections[item.snapshot.trackerID]
                    )
                }

                HStack(spacing: 14) {
                    legendItem(color: theme.textPrimary, label: "Target", isTick: true)
                    legendItem(color: theme.accent.opacity(0.25), label: "Projected")
                }
                .padding(.top, 2)
            }
        }
    }

    private func legendItem(color: Color, label: String, isTick: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: isTick ? 2.5 : 12, height: isTick ? 12 : 8)
            Text(label)
                .font(theme.typography.label)
                .foregroundStyle(theme.textSecondary)
        }
    }
}

#Preview("Bullet chart") {
    let sample = SampleData.previewTracker()
    let snapshot = ProgressEngine().currentSnapshot(
        tracker: sample.tracker, entries: sample.entries
    )

    return VStack(spacing: 20) {
        TrackerCard(title: "Today", subtitle: "Measure against target") {
            BulletChartView(snapshot: snapshot, title: "Focus Time", projected: 72)
        }

        TrackerCard(title: "All goals") {
            BulletChartList(
                items: [
                    ("Focus Time", snapshot),
                    ("Water", snapshot),
                    ("Steps", snapshot)
                ]
            )
        }
    }
    .padding()
}
