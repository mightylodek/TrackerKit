import SwiftUI

// MARK: - HeroStyle

/// Which hero treatment to render. All four take the same inputs, so a host app
/// can switch presentation without rebuilding its data.
public enum HeroStyle: String, Sendable, CaseIterable {
    /// Concentric rings plus the streak. The "today at a glance" opener.
    case rings
    /// One enormous number with a sparkline under it. For a single headline metric.
    case headline
    /// Stoplight rollup across every goal. The parent's overview.
    case summary
    /// Compact greeting bar — name, streak, one status line. For screens where the
    /// hero should not dominate.
    case compact
}

// MARK: - HeroSectionView

/// The top-of-screen block.
///
/// A hero is the one place in a dashboard where a big number earns its space, so
/// this deliberately shows *few* things large rather than many things small. The
/// detail lives below it.
public struct HeroSectionView: View {
    @Environment(\.trackerTheme) private var theme

    private let style: HeroStyle
    private let profile: Profile?
    private let snapshots: [ProgressSnapshot]
    private let trackers: [Tracker]
    private let loginStreak: StreakSummary
    private let streakDays: [(date: Date, isActive: Bool)]
    private let headlineTracker: Tracker?
    private let headlineValues: [DailyValue]
    private let greeting: String?

    public init(
        style: HeroStyle = .rings,
        profile: Profile?,
        trackers: [Tracker],
        snapshots: [ProgressSnapshot],
        loginStreak: StreakSummary,
        streakDays: [(date: Date, isActive: Bool)] = [],
        headlineTracker: Tracker? = nil,
        headlineValues: [DailyValue] = [],
        greeting: String? = nil
    ) {
        self.style = style
        self.profile = profile
        self.trackers = trackers
        self.snapshots = snapshots
        self.loginStreak = loginStreak
        self.streakDays = streakDays
        self.headlineTracker = headlineTracker
        self.headlineValues = headlineValues
        self.greeting = greeting
    }

    private var accent: Color {
        // The hero leans on the app's brand, not the profile's stored hue, so a
        // monochrome theme stays monochrome.
        profile.map { theme.identityColor(for: $0) } ?? theme.accent
    }

    private var scored: [ProgressSnapshot] { snapshots.filter { $0.status != .neutral } }
    private var greenCount: Int { snapshots.filter { $0.status == .green }.count }

    public var body: some View {
        switch style {
        case .rings: ringsHero
        case .headline: headlineHero
        case .summary: summaryHero
        case .compact: compactHero
        }
    }

    // MARK: Rings

    private var ringsHero: some View {
        VStack(spacing: 18) {
            greetingRow

            ProgressRingsView(
                rings: ringData,
                size: 210,
                lineWidth: theme.metrics.ringWidth,
                spacing: theme.metrics.ringSpacing,
                showsLegend: true
            ) {
                VStack(spacing: -2) {
                    Text("\(greenCount)")
                        .font(theme.typography.displaySize(46))
                        .monospacedDigit()
                        .tracking(theme.typography.displayTracking)
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("of \(max(scored.count, 1)) met")
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(heroBackground)
    }

    /// Up to three rings: the most interesting goals, not simply the first three.
    /// Anything already met is deprioritized — a finished ring is the least
    /// useful thing to stare at.
    private var ringData: [RingData] {
        let byID = Dictionary(uniqueKeysWithValues: trackers.map { ($0.id, $0) })
        return snapshots
            .filter { $0.goal != nil }
            .sorted { lhs, rhs in
                if lhs.isMet != rhs.isMet { return !lhs.isMet }
                return lhs.status > rhs.status
            }
            .prefix(3)
            .compactMap { snapshot in
                guard let tracker = byID[snapshot.trackerID] else { return nil }
                return RingData.from(snapshot: snapshot, tracker: tracker, color: theme.identityColor(for: tracker))
            }
    }

    // MARK: Headline

    private var headlineHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            greetingRow

            if let tracker = headlineTracker,
               let snapshot = snapshots.first(where: { $0.trackerID == tracker.id }) {

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: tracker.symbolName)
                        .font(.title3)
                        .foregroundStyle(theme.identityColor(for: tracker))
                    Text(tracker.title)
                        .font(theme.typography.heading)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    StoplightBadge(status: snapshot.status, size: .small)
                }

                CountUpText(
                    value: snapshot.actual,
                    unit: snapshot.unit,
                    font: .system(size: 64, weight: .bold, design: .rounded),
                    color: theme.textPrimary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.5)

                if let target = snapshot.target {
                    Text("of \(Formatters.value(target, unit: snapshot.unit)) \(snapshot.goal?.cadence.displayName.lowercased() ?? "")")
                        .font(theme.typography.subheadline)
                        .foregroundStyle(theme.textMuted)
                }

                if !headlineValues.isEmpty {
                    SparklineView(
                        dailyValues: headlineValues,
                        color: theme.identityColor(for: tracker),
                        style: .filledLine,
                        goalLine: snapshot.target
                    )
                    .frame(height: 54)
                    .padding(.top, 4)
                }
            } else {
                Text("Pick a headline tracker to feature here.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(theme.spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
    }

    // MARK: Summary

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            greetingRow

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(greenCount)")
                            .font(theme.typography.displaySize(46))
                            .monospacedDigit()
                            .tracking(theme.typography.displayTracking)
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("/ \(max(scored.count, 1))")
                            .font(.title3.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(theme.textMuted)
                    }
                    Text("goals on track")
                        .font(theme.typography.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                StreakBadge(streak: loginStreak, size: .regular, color: accent)
            }

            StoplightSummaryBar(snapshots: snapshots)

            if !streakDays.isEmpty {
                StreakCalendarStrip(days: streakDays, color: accent, pipSize: 22, showsLabels: true)
            }
        }
        .padding(theme.spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
    }

    // MARK: Compact

    private var compactHero: some View {
        HStack(spacing: 14) {
            ProfileAvatar(profile: profile, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(greeting ?? defaultGreeting)
                    .font(theme.typography.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(statusLine)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            StreakBadge(streak: loginStreak, size: .compact, color: accent)
        }
        .padding(.horizontal, theme.spacing.cardPadding)
        .padding(.vertical, 12)
        .background(heroBackground)
    }

    // MARK: Shared pieces

    private var greetingRow: some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: profile, size: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(greeting ?? defaultGreeting)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textMuted)
            }

            Spacer()

            if style != .summary {
                StreakBadge(streak: loginStreak, size: .compact, color: accent)
            }
        }
        .padding(.horizontal, style == .rings ? theme.spacing.cardPadding : 0)
    }

    private var defaultGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = profile?.name ?? "there"
        switch hour {
        case 0..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }

    private var statusLine: String {
        guard !scored.isEmpty else { return "No goals set yet" }
        let red = snapshots.filter { $0.status == .red }.count
        if red > 0 { return "\(greenCount) on track · \(red) needs attention" }
        return "\(greenCount) of \(scored.count) goals on track"
    }

    /// The hero's atmosphere.
    ///
    /// Two offset radial blooms over the surface rather than one flat linear
    /// gradient — a single corner-to-corner ramp reads as a coloured rectangle,
    /// whereas offset blooms read as light in a space, which is what gives the
    /// hero depth against the flat cards below it.
    ///
    /// The second bloom is tinted by the **worst status across every goal**, so
    /// the ambient colour of the screen carries information: it warms toward
    /// amber and red when something needs attention, and stays cool when it
    /// doesn't. You register it before reading a single number.
    private var heroBackground: some View {
        let wash = theme.surfaces.heroWash

        return ZStack {
            theme.surface

            RadialGradient(
                colors: [accent.opacity(wash * 1.15), accent.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 0,
                endRadius: 280
            )

            RadialGradient(
                colors: [ambientStatusTint.opacity(wash * 0.42), .clear],
                center: UnitPoint(x: 0.9, y: 0.92),
                startRadius: 0,
                endRadius: 220
            )
        }
        .clipShape(theme.radii.cardShape)
        .overlay {
            theme.radii.cardShape.stroke(theme.border, lineWidth: 1)
        }
        .animation(theme.motion.fillAnimation, value: ambientStatusTint)
    }

    /// The colour the hero's ambient light leans toward.
    ///
    /// Falls back to the accent when nothing is scored, so an empty profile gets
    /// brand colour rather than a grey wash that reads as broken.
    private var ambientStatusTint: Color {
        let worst = scored.map(\.status).max() ?? .neutral
        return worst == .neutral ? accent : theme.statusColor(worst)
    }
}

// MARK: - ProfileAvatar

/// Circular profile mark: symbol on the profile's own color, initials as fallback.
public struct ProfileAvatar: View {
    @Environment(\.trackerTheme) private var theme

    private let profile: Profile?
    private let size: CGFloat
    private let showsRing: Bool

    public init(profile: Profile?, size: CGFloat = 44, showsRing: Bool = false) {
        self.profile = profile
        self.size = size
        self.showsRing = showsRing
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill((profile.map { theme.identityColor(for: $0) } ?? theme.textMuted).gradient)

            if let profile, !profile.symbolName.isEmpty, profile.symbolName != "person.fill" {
                Image(systemName: profile.symbolName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            } else if let initials = profile?.initials, !initials.isEmpty {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.44))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showsRing {
                Circle().strokeBorder(theme.surface, lineWidth: 2)
            }
        }
        .accessibilityLabel(profile?.name ?? "No profile")
    }
}

#Preview("Hero styles") {
    let store = TrackerStore.preview()
    let snapshots = store.currentProgressAll()
    let streak = store.loginStreak()
    let flags = StreakEngine().activityFlags(days: store.loginDays.map(\.day), dayCount: 14)
    let headline = store.activeTrackers.first
    let values = headline.map { store.dailyValues(for: $0.id, dayCount: 30) } ?? []

    return ScrollView {
        VStack(spacing: 20) {
            ForEach(HeroStyle.allCases, id: \.self) { style in
                HeroSectionView(
                    style: style,
                    profile: store.activeProfile,
                    trackers: store.activeTrackers,
                    snapshots: snapshots,
                    loginStreak: streak,
                    streakDays: flags,
                    headlineTracker: headline,
                    headlineValues: values
                )
            }
        }
        .padding()
    }
}
