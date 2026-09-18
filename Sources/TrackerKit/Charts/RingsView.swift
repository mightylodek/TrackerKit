import SwiftUI

// MARK: - RingData

/// One ring in a ring stack.
public struct RingData: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var label: String
    /// Completion, uncapped — values over 1 render as a second lap rather than
    /// being clipped, so beating a goal is visible instead of invisible.
    public var fraction: Double
    public var colorHex: String
    public var symbolName: String?
    public var valueText: String?
    public var status: StoplightStatus
    /// True when this ring tracks an `.atMost` goal that has been exceeded.
    ///
    /// Rings inherit an assumption from Apple's Activity rings that more is
    /// always better. That is false for a ceiling — a screen-time ring at 115%
    /// looks like a win and is a loss. The overshoot is drawn in the critical
    /// colour so a breach cannot be mistaken for an achievement.
    public var breachesLimit: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        fraction: Double,
        colorHex: String,
        symbolName: String? = nil,
        valueText: String? = nil,
        status: StoplightStatus = .neutral,
        breachesLimit: Bool = false
    ) {
        self.id = id
        self.label = label
        self.fraction = fraction.isFinite ? max(0, fraction) : 0
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.valueText = valueText
        self.status = status
        self.breachesLimit = breachesLimit
    }

    public var color: Color { Color(hex: colorHex) }
    public var laps: Int { Int(fraction) }
    public var isComplete: Bool { fraction >= 1 }

    /// Builds a ring from a scored period.
    /// - Parameter color: the theme-resolved identity colour. Passed in rather
    ///   than read off the tracker so a monochrome theme can override the stored
    ///   hue without rewriting stored data.
    public static func from(
        snapshot: ProgressSnapshot,
        tracker: Tracker,
        color: Color? = nil
    ) -> RingData {
        RingData(
            id: tracker.id,
            label: tracker.title,
            fraction: snapshot.fraction ?? 0,
            colorHex: color?.hexString ?? tracker.colorHex,
            symbolName: tracker.symbolName,
            valueText: Formatters.value(snapshot.actual, unit: snapshot.unit),
            status: snapshot.status,
            breachesLimit: snapshot.direction == .atMost
                && snapshot.target.map { snapshot.actual > $0 } == true
        )
    }
}

// MARK: - ProgressRing

/// A single ring. Sweeps from the top, clockwise, with a rounded cap.
public struct ProgressRing: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    private let ring: RingData
    private let lineWidth: CGFloat
    public init(ring: RingData, lineWidth: CGFloat? = nil) {
        self.ring = ring
        self.lineWidth = lineWidth ?? 14
    }

    private var displayed: Double { reduceMotion ? ring.fraction : animated }

    public var body: some View {
        ZStack {
            // Track.
            Circle()
                .stroke(ring.color.opacity(0.18), lineWidth: lineWidth)

            // Completed laps sit underneath at reduced opacity, so a 2.4× result
            // reads as "went around twice and then some".
            if ring.laps >= 1 {
                Circle()
                    .stroke(
                        ring.color.opacity(0.55),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            }

            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(
                    AngularGradient(
                        colors: [arcColor.opacity(0.75), arcColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: arcColor.opacity(ring.isComplete ? 0.45 : 0), radius: 6)
        }
        .onAppear(perform: animateIn)
        .onChange(of: ring.fraction) { _, newValue in
            withAnimation(theme.motion.fillAnimation) { animated = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.label), \(Formatters.percent(ring.fraction)) of goal")
    }

    /// The colour of the leading arc. A breached ceiling turns critical so the
    /// ring stops congratulating the user for overshooting a limit.
    private var arcColor: Color {
        ring.breachesLimit ? theme.statusColor(.red) : ring.color
    }

    /// The visible arc for the *current* lap. A fraction of 2.4 draws a full
    /// completed lap underneath plus a 0.4 arc on top, so overachievement reads
    /// as "went around and kept going" instead of a bar that silently caps.
    private var arcFraction: Double {
        let value = displayed
        guard value > 0 else { return 0 }
        guard value >= 1 else { return value }
        let remainder = value - Double(Int(value))
        return remainder == 0 ? 1 : remainder
    }

    private func animateIn() {
        guard theme.motion.animatesOnAppear, !reduceMotion else {
            animated = ring.fraction
            return
        }
        animated = 0
        withAnimation(theme.motion.fillAnimation) { animated = ring.fraction }
    }
}

// MARK: - ProgressRingsView

/// Concentric rings — the "three rings" glance, generalized.
///
/// Best at three; tolerable at four. Past that the inner rings get too small to
/// read and a ``BulletChartList`` communicates the same thing better. The view
/// caps at five and says so rather than drawing something illegible.
public struct ProgressRingsView: View {
    @Environment(\.trackerTheme) private var theme

    private let rings: [RingData]
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let spacing: CGFloat
    private let showsLegend: Bool
    private let centerContent: AnyView?

    public init(
        rings: [RingData],
        size: CGFloat = 180,
        lineWidth: CGFloat? = nil,
        spacing: CGFloat? = nil,
        showsLegend: Bool = true
    ) {
        self.rings = Array(rings.prefix(5))
        self.size = size
        self.lineWidth = lineWidth ?? 16
        self.spacing = spacing ?? 6
        self.showsLegend = showsLegend
        self.centerContent = nil
    }

    /// With custom content in the middle — a streak count, a date, a total.
    public init<Center: View>(
        rings: [RingData],
        size: CGFloat = 180,
        lineWidth: CGFloat? = nil,
        spacing: CGFloat? = nil,
        showsLegend: Bool = true,
        @ViewBuilder center: () -> Center
    ) {
        self.rings = Array(rings.prefix(5))
        self.size = size
        self.lineWidth = lineWidth ?? 16
        self.spacing = spacing ?? 6
        self.showsLegend = showsLegend
        self.centerContent = AnyView(center())
    }

    public var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let inset = CGFloat(index) * (lineWidth + spacing)
                    ProgressRing(ring: ring, lineWidth: lineWidth)
                        .frame(width: size - inset * 2, height: size - inset * 2)
                }

                if let centerContent {
                    centerContent
                        .frame(maxWidth: size - CGFloat(rings.count) * (lineWidth + spacing) * 2)
                }
            }
            .frame(width: size, height: size)

            if showsLegend {
                legend
            }
        }
    }

    /// Ring identity is carried by label and value, not by ring position — nobody
    /// remembers which ring is the outer one.
    private var legend: some View {
        VStack(spacing: 6) {
            ForEach(rings) { ring in
                HStack(spacing: 8) {
                    if let symbol = ring.symbolName {
                        Image(systemName: symbol)
                            .font(theme.typography.label)
                            .foregroundStyle(ring.color)
                            .frame(width: 16)
                    } else {
                        Circle()
                            .fill(ring.color)
                            .frame(width: 8, height: 8)
                            .frame(width: 16)
                    }

                    Text(ring.label)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if let valueText = ring.valueText {
                        Text(valueText)
                            .font(theme.typography.label.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }

                    Text(Formatters.percent(ring.fraction))
                        .font(theme.typography.micro.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - RadialProgressView

/// A single ring with the number in the middle. The compact form used in widgets
/// and list rows.
public struct RadialProgressView: View {
    @Environment(\.trackerTheme) private var theme

    private let fraction: Double
    private let color: Color
    private let label: String?
    private let valueText: String?
    private let size: CGFloat
    private let lineWidth: CGFloat

    public init(
        fraction: Double,
        color: Color,
        label: String? = nil,
        valueText: String? = nil,
        size: CGFloat = 76,
        lineWidth: CGFloat? = nil
    ) {
        self.fraction = fraction
        self.color = color
        self.label = label
        self.valueText = valueText
        self.size = size
        self.lineWidth = lineWidth ?? max(6, size * 0.13)
    }

    public init(snapshot: ProgressSnapshot, color: Color, size: CGFloat = 76) {
        self.init(
            fraction: snapshot.fraction ?? 0,
            color: color,
            valueText: Formatters.percent(snapshot.clampedFraction),
            size: size
        )
    }

    public var body: some View {
        ProgressRing(
            ring: RingData(
                label: label ?? "Progress",
                fraction: fraction,
                colorHex: color.hexString
            ),
            lineWidth: lineWidth
        )
        .frame(width: size, height: size)
        .overlay {
            VStack(spacing: 0) {
                if let valueText {
                    Text(valueText)
                        .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                if let label, size >= 90 {
                    Text(label)
                        .font(.system(size: size * 0.11))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(size * 0.22)
        }
    }
}

#Preview("Rings") {
    let palette = ChartPalette.standard
    let rings = [
        RingData(label: "Focus Time", fraction: 1.25, colorHex: palette.seriesHex(0),
                 symbolName: "brain.head.profile", valueText: "75 min", status: .green),
        RingData(label: "Water", fraction: 0.62, colorHex: palette.seriesHex(2),
                 symbolName: "drop.fill", valueText: "5 glasses", status: .yellow),
        RingData(label: "Steps", fraction: 0.35, colorHex: palette.seriesHex(1),
                 symbolName: "shoeprints.fill", valueText: "2,800", status: .red)
    ]

    return TrackerCard(title: "Today") {
        ProgressRingsView(rings: rings, size: 200) {
            VStack(spacing: 0) {
                Text("3")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    .padding()
}
