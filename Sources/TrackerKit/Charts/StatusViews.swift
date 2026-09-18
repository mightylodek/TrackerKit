import SwiftUI

// MARK: - StoplightBadge

/// Status as a pill: color, icon **and** word.
///
/// The icon and the word are not decoration. Status colors are the one palette
/// where red/green carry the entire meaning, which is exactly the pairing a
/// red-green colorblind viewer cannot resolve — roughly 1 in 12 men. Every
/// stoplight in this library therefore ships with a shape and a label.
public struct StoplightBadge: View {
    @Environment(\.trackerTheme) private var theme

    public enum Size: Sendable { case small, medium, large }

    private let status: StoplightStatus
    private let text: String?
    private let size: Size
    private let showsLabel: Bool

    public init(
        status: StoplightStatus,
        text: String? = nil,
        size: Size = .medium,
        showsLabel: Bool = true
    ) {
        self.status = status
        self.text = text
        self.size = size
        self.showsLabel = showsLabel
    }

    private var font: Font {
        switch size {
        case .small: .caption2.weight(.semibold)
        case .medium: .caption.weight(.semibold)
        case .large: .subheadline.weight(.semibold)
        }
    }

    private var padding: (h: CGFloat, v: CGFloat) {
        switch size {
        case .small: (7, 3)
        case .medium: (9, 4)
        case .large: (12, 6)
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .font(font)
                // The badge reacts when the verdict changes, so a goal tipping
                // from at-risk to on-track is something you notice rather than
                // something you have to go looking for.
                .symbolEffect(.bounce, value: status)
                .contentTransition(.symbolEffect(.replace))
            if showsLabel {
                Text(text ?? status.displayName)
                    .font(font)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(theme.statusColor(status))
        .padding(.horizontal, showsLabel ? padding.h : padding.v)
        .padding(.vertical, padding.v)
        .background {
            Capsule().fill(theme.statusColor(status).opacity(0.12))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text ?? status.displayName)
    }
}

// MARK: - StoplightDot

/// The smallest possible status mark, for list rows and widget corners.
/// Shape differs per status so it survives grayscale.
public struct StoplightDot: View {
    @Environment(\.trackerTheme) private var theme

    private let status: StoplightStatus
    private let size: CGFloat

    public init(status: StoplightStatus, size: CGFloat = 10) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Group {
            switch status {
            case .green:
                Circle().fill(theme.statusColor(.green))
            case .yellow:
                Triangle().fill(theme.statusColor(.yellow))
            case .red:
                RoundedRectangle(cornerRadius: size * 0.2).fill(theme.statusColor(.red))
            case .neutral:
                Circle().strokeBorder(theme.textMuted, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(status.displayName)
    }
}

/// Equilateral-ish triangle used by the "at risk" dot.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - StoplightSummaryBar

/// A one-line rollup of how many goals sit at each status — the parent's glance.
public struct StoplightSummaryBar: View {
    @Environment(\.trackerTheme) private var theme

    private let snapshots: [ProgressSnapshot]
    private let showsCounts: Bool

    public init(snapshots: [ProgressSnapshot], showsCounts: Bool = true) {
        self.snapshots = snapshots
        self.showsCounts = showsCounts
    }

    private var counts: [(status: StoplightStatus, count: Int)] {
        let ordered: [StoplightStatus] = [.green, .yellow, .red, .neutral]
        return ordered.compactMap { status in
            let count = snapshots.filter { $0.status == status }.count
            return count > 0 ? (status, count) : nil
        }
    }

    private var total: Int { max(snapshots.count, 1) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: theme.metrics.surfaceGap) {
                    ForEach(counts, id: \.status) { entry in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.statusColor(entry.status))
                            .frame(
                                width: max(
                                    4,
                                    (geometry.size.width - CGFloat(counts.count - 1) * theme.metrics.surfaceGap)
                                        * CGFloat(entry.count) / CGFloat(total)
                                )
                            )
                    }
                }
            }
            .frame(height: 8)

            if showsCounts {
                FlowLayout(spacing: 12) {
                    ForEach(counts, id: \.status) { entry in
                        HStack(spacing: 5) {
                            StoplightDot(status: entry.status, size: 8)
                            Text("\(entry.count) \(entry.status.displayName.lowercased())")
                                .font(theme.typography.label)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - GaugeChartView

/// A semicircular gauge with stoplight zones.
///
/// Included because it is asked for, with a caveat worth stating: a gauge spends
/// a lot of screen to show one number, and the zones are easy to misread at a
/// glance. ``BulletChartView`` carries the same information in a fifth of the
/// space and compares cleanly across rows. Reach for a gauge when a single
/// hero number needs presence — a dashboard's one headline metric — not when
/// several need comparing.
public struct GaugeChartView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    private let value: Double
    private let target: Double?
    private let unit: String
    private let status: StoplightStatus
    private let label: String?
    private let size: CGFloat
    private let showsZones: Bool

    public init(
        value: Double,
        target: Double?,
        unit: String = "",
        status: StoplightStatus = .neutral,
        label: String? = nil,
        size: CGFloat = 170,
        showsZones: Bool = true
    ) {
        self.value = value
        self.target = target
        self.unit = unit
        self.status = status
        self.label = label
        self.size = size
        self.showsZones = showsZones
    }

    public init(snapshot: ProgressSnapshot, label: String? = nil, size: CGFloat = 170) {
        self.init(
            value: snapshot.actual,
            target: snapshot.target,
            unit: snapshot.unit,
            status: snapshot.status,
            label: label,
            size: size
        )
    }

    /// Scale runs to 125% of target so beating it stays on the dial.
    private var scaleMax: Double {
        guard let target, target > 0 else { return max(value, 1) }
        return max(target * 1.25, value)
    }

    private var fraction: Double {
        min(max(value / scaleMax, 0), 1)
    }

    /// Sweep spans 240°, from 150° round to 30° — the familiar dial opening.
    private let sweep: Double = 240
    private let startAngle: Double = 150

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if showsZones, target != nil {
                    zoneArcs
                } else {
                    arc(from: 0, to: 1)
                        .stroke(theme.gridline, style: .init(lineWidth: size * 0.09, lineCap: .round))
                }

                arc(from: 0, to: reduceMotion ? fraction : animated)
                    .stroke(
                        theme.statusColor(status == .neutral ? .green : status),
                        style: .init(lineWidth: size * 0.09, lineCap: .round)
                    )

                if let target, target > 0, target <= scaleMax {
                    targetTick(at: target / scaleMax)
                }

                readout
            }
            .frame(width: size, height: size * 0.72)

            if let label {
                Text(label)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .onAppear {
            guard theme.motion.animatesOnAppear, !reduceMotion else {
                animated = fraction
                return
            }
            withAnimation(theme.motion.fillAnimation) { animated = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(theme.motion.fillAnimation) { animated = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(label ?? "Gauge"), \(Formatters.value(value, unit: unit))"
            + (target.map { " of \(Formatters.value($0, unit: unit))" } ?? "")
            + ", \(status.displayName)"
        )
    }

    // MARK: Pieces

    /// Background zones in muted status tints. Deliberately washed out so the
    /// value arc, not the background, is what the eye lands on.
    private var zoneArcs: some View {
        ZStack {
            arc(from: 0, to: 0.6)
                .stroke(theme.statusColor(.red).opacity(0.18), style: .init(lineWidth: size * 0.09, lineCap: .round))
            arc(from: 0.6, to: 0.8)
                .stroke(theme.statusColor(.yellow).opacity(0.22), style: .init(lineWidth: size * 0.09))
            arc(from: 0.8, to: 1)
                .stroke(theme.statusColor(.green).opacity(0.2), style: .init(lineWidth: size * 0.09, lineCap: .round))
        }
    }

    private func arc(from start: Double, to end: Double) -> Path {
        Path { path in
            let center = CGPoint(x: size / 2, y: size * 0.36 + size * 0.09)
            let radius = size / 2 - size * 0.09
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startAngle + sweep * start),
                endAngle: .degrees(startAngle + sweep * max(end, start)),
                clockwise: false
            )
        }
    }

    private func targetTick(at fraction: Double) -> some View {
        let angle = Angle.degrees(startAngle + sweep * fraction)
        let radius = size / 2 - size * 0.09
        let center = CGPoint(x: size / 2, y: size * 0.36 + size * 0.09)
        let x = center.x + cos(angle.radians) * radius
        let y = center.y + sin(angle.radians) * radius

        return Rectangle()
            .fill(theme.textPrimary)
            .frame(width: 2.5, height: size * 0.11)
            .overlay { Rectangle().strokeBorder(theme.surface, lineWidth: 0.75) }
            .rotationEffect(angle + .degrees(90))
            .position(x: x, y: y)
    }

    private var readout: some View {
        VStack(spacing: 1) {
            Text(Formatters.value(value, unit: unit))
                .font(.system(size: size * 0.17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if let target {
                Text("of \(Formatters.value(target, unit: unit))")
                    .font(.system(size: size * 0.075))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .offset(y: size * 0.06)
    }
}

#Preview("Status visuals") {
    let sample = SampleData.previewTracker()
    let snapshots = ProgressEngine().history(
        tracker: sample.tracker, entries: sample.entries, periodCount: 6, cadence: .weekly
    )

    return VStack(spacing: 18) {
        TrackerCard(title: "Badges") {
            FlowLayout(spacing: 8) {
                StoplightBadge(status: .green)
                StoplightBadge(status: .yellow)
                StoplightBadge(status: .red)
                StoplightBadge(status: .neutral)
            }
        }

        TrackerCard(title: "Rollup") {
            StoplightSummaryBar(snapshots: snapshots)
        }

        TrackerCard(title: "Gauge") {
            GaugeChartView(
                value: 74, target: 60, unit: "min", status: .green, label: "Focus today"
            )
            .frame(maxWidth: .infinity)
        }
    }
    .padding()
}
