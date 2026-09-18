import SwiftUI

// MARK: - StreakCalendarStrip

/// The chain: one pip per day, filled when the day counted.
///
/// Consecutive active days are joined by a connecting bar, which is the entire
/// point — the eye reads an unbroken run as one object and a gap as damage. That
/// visual "chain" is what makes streaks motivating, so the connector is load
/// bearing, not decoration.
public struct StreakCalendarStrip: View {
    @Environment(\.trackerTheme) private var theme

    private let days: [(date: Date, isActive: Bool)]
    private let color: Color
    private let pipSize: CGFloat
    private let showsLabels: Bool

    public init(
        days: [(date: Date, isActive: Bool)],
        color: Color,
        pipSize: CGFloat = 26,
        showsLabels: Bool = true
    ) {
        self.days = days
        self.color = color
        self.pipSize = pipSize
        self.showsLabels = showsLabels
    }

    /// Builds the strip from login history.
    public init(
        loginDays: [LoginDay],
        dayCount: Int = 14,
        color: Color,
        engine: StreakEngine = StreakEngine(),
        pipSize: CGFloat = 26
    ) {
        self.days = engine.activityFlags(days: loginDays.map(\.day), dayCount: dayCount)
        self.color = color
        self.pipSize = pipSize
        self.showsLabels = true
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 5) {
                    ZStack {
                        // Connector to the previous day, drawn behind the pips.
                        if index > 0, day.isActive, days[index - 1].isActive {
                            Rectangle()
                                .fill(color)
                                .frame(height: pipSize * 0.2)
                                .offset(x: -pipSize * 0.5)
                        }

                        pip(for: day)
                    }
                    .frame(width: pipSize, height: pipSize)

                    if showsLabels {
                        Text(Formatters.weekdayShort(day.date).prefix(1))
                            // Was 9pt. Below caption2, which is already too small
                            // for anything a person has to read rather than scan.
                            .font(theme.typography.micro)
                            .foregroundStyle(
                                Calendar.current.isDateInToday(day.date)
                                    ? theme.textPrimary
                                    : theme.textMuted
                            )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(days.filter(\.isActive).count) of \(days.count) recent days active"
        )
    }

    @ViewBuilder
    private func pip(for day: (date: Date, isActive: Bool)) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)

        if day.isActive {
            Circle()
                .fill(color)
                .frame(width: pipSize * 0.8, height: pipSize * 0.8)
                .overlay {
                    if isToday {
                        Circle().strokeBorder(theme.surface, lineWidth: 2)
                    }
                }
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: pipSize * 0.34, weight: .bold))
                        .foregroundStyle(theme.surface)
                }
        } else {
            Circle()
                .strokeBorder(
                    isToday ? color.opacity(0.7) : theme.gridline,
                    style: StrokeStyle(lineWidth: isToday ? 2 : 1.5, dash: isToday ? [3, 2] : [])
                )
                .frame(width: pipSize * 0.8, height: pipSize * 0.8)
        }
    }
}

// MARK: - StreakBadge

/// The headline streak number with its flame. Scales from a list row to a hero.
public struct StreakBadge: View {
    @Environment(\.trackerTheme) private var theme

    public enum Size: Sendable { case compact, regular, hero }

    private let streak: StreakSummary
    private let size: Size
    private let color: Color

    public init(streak: StreakSummary, size: Size = .regular, color: Color? = nil) {
        self.streak = streak
        self.size = size
        self.color = color ?? Color(hex: "#eb6834")
    }

    private var numberFont: Font {
        switch size {
        case .compact: .headline.weight(.bold)
        case .regular: .system(size: 34, weight: .bold, design: .rounded)
        case .hero: .system(size: 56, weight: .bold, design: .rounded)
        }
    }

    private var symbolFont: Font {
        switch size {
        case .compact: .caption
        case .regular: .title3
        case .hero: .largeTitle
        }
    }

    public var body: some View {
        HStack(spacing: size == .compact ? 4 : 8) {
            Image(systemName: streak.current > 0 ? "flame.fill" : "flame")
                .font(symbolFont)
                .foregroundStyle(
                    streak.current > 0
                        ? AnyShapeStyle(LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        : AnyShapeStyle(theme.textMuted)
                )
                .symbolEffect(.pulse, options: .repeat(.continuous), isActive: streak.isAtRisk)

            VStack(alignment: .leading, spacing: -2) {
                Text("\(streak.current)")
                    .font(numberFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())

                if size != .compact {
                    Text(streak.current == 1 ? "day streak" : "day streak")
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if size == .hero, streak.isPersonalBest, streak.current > 1 {
                Text("BEST")
                    .font(theme.typography.micro.weight(.heavy))
                    .foregroundStyle(theme.surface)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(color))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.current) day streak\(streak.isAtRisk ? ", at risk today" : "")")
    }
}

// MARK: - StreakCard

/// Streak number, chain and the at-risk nudge in one block.
public struct StreakCard: View {
    @Environment(\.trackerTheme) private var theme

    private let streak: StreakSummary
    private let days: [(date: Date, isActive: Bool)]
    private let color: Color
    private let title: String

    public init(
        streak: StreakSummary,
        days: [(date: Date, isActive: Bool)],
        color: Color? = nil,
        title: String = "Login streak"
    ) {
        self.streak = streak
        self.days = days
        self.color = color ?? Color(hex: "#eb6834")
        self.title = title
    }

    public var body: some View {
        TrackerCard(title: title) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    StreakBadge(streak: streak, size: .regular, color: color)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Best")
                            .font(theme.typography.micro)
                            .foregroundStyle(theme.textMuted)
                        Text("\(streak.longest)")
                            .font(theme.typography.heading)
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                StreakCalendarStrip(days: days, color: color)

                if streak.isAtRisk {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(theme.typography.label)
                        Text("Log today to keep the streak alive")
                            .font(theme.typography.label)
                    }
                    .foregroundStyle(theme.statusColor(.yellow))
                } else if streak.isActiveToday, streak.current > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(theme.typography.label)
                        Text("Today is locked in")
                            .font(theme.typography.label)
                    }
                    .foregroundStyle(theme.statusColor(.green))
                }
            }
        }
    }
}

#Preview("Streaks") {
    let engine = StreakEngine()
    let calendar = Calendar.current
    let days: [Date] = (0..<20).compactMap { offset in
        guard offset != 5, offset != 6, offset != 13 else { return nil }
        return calendar.date(byAdding: .day, value: -offset, to: .now)
    }
    let summary = engine.summary(days: days)
    let flags = engine.activityFlags(days: days, dayCount: 14)

    return VStack(spacing: 18) {
        StreakCard(streak: summary, days: flags)
        TrackerCard(title: "Hero badge") {
            StreakBadge(streak: summary, size: .hero)
        }
    }
    .padding()
}
