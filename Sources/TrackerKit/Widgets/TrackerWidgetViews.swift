import SwiftUI

// MARK: - TrackerWidgetSize

/// Which widget family a view is rendering for. Named separately from
/// `WidgetFamily` so these views compile and preview inside the app too, without
/// the host needing a widget extension.
public enum TrackerWidgetSize: String, Sendable, CaseIterable {
    case small
    case medium
    case large

    public var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Canonical dimensions, used by the in-app gallery to show true-to-life tiles.
    public var previewSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

// MARK: - TrackerWidgetView

/// The widget body. Point a WidgetKit `TimelineProvider` at a ``WidgetSnapshot``
/// and hand it here; the same view also renders inline in the app.
///
/// Each size shows a genuinely different amount rather than the same layout
/// scaled — a small widget with six shrunken rows is unreadable at arm's length,
/// which is the only distance a widget is ever read from.
public struct TrackerWidgetView: View {
    @Environment(\.trackerTheme) private var theme

    private let snapshot: WidgetSnapshot
    private let size: TrackerWidgetSize
    private let linksToTrackers: Bool

    /// - Parameter linksToTrackers: wraps each row in a deep link so a tap lands
    ///   on that tracker rather than the dashboard. Off for previews and the
    ///   in-app gallery, where a `Link` would be inert or actively confusing.
    public init(
        snapshot: WidgetSnapshot,
        size: TrackerWidgetSize,
        linksToTrackers: Bool = false
    ) {
        self.snapshot = snapshot
        self.size = size
        self.linksToTrackers = linksToTrackers
    }

    /// Wraps a row in a deep link when links are enabled.
    @ViewBuilder
    private func linked<Content: View>(
        _ id: UUID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if linksToTrackers {
            Link(destination: WidgetDeepLink.tracker(id).url) { content() }
        } else {
            content()
        }
    }

    private var accent: Color { Color(hex: snapshot.profileColorHex) }

    public var body: some View {
        switch size {
        case .small: smallBody
        case .medium: mediumBody
        case .large: largeBody
        }
    }

    // MARK: Small — one ring, one number

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(theme.typography.micro)
                    .foregroundStyle(accent)
                Text("\(snapshot.loginStreak)")
                    .font(theme.typography.label.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                StoplightDot(status: snapshot.worstStatus, size: 8)
            }

            Spacer(minLength: 6)

            if let line = snapshot.lines.first {
                HStack {
                    Spacer()
                    RadialProgressView(
                        fraction: line.fraction,
                        color: Color(hex: line.colorHex),
                        valueText: Formatters.percent(min(line.fraction, 1)),
                        size: 74
                    )
                    Spacer()
                }

                Spacer(minLength: 6)

                Text(line.title)
                    .font(theme.typography.micro.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(line.progressText)
                    .font(theme.typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            } else {
                emptyLine
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium — rings plus two lines

    private var mediumBody: some View {
        HStack(spacing: 14) {
            ProgressRingsView(
                rings: rings(limit: 3),
                size: 108,
                lineWidth: 11,
                spacing: 4,
                showsLegend: false
            ) {
                VStack(spacing: -1) {
                    Text("\(snapshot.greenCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                    Text("of \(max(snapshot.scoredCount, 1))")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textMuted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text(snapshot.profileName)
                        .font(theme.typography.label.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Image(systemName: "flame.fill")
                        .font(theme.typography.micro)
                        .foregroundStyle(accent)
                    Text("\(snapshot.loginStreak)")
                        .font(theme.typography.label.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                }

                ForEach(snapshot.lines.prefix(3)) { line in
                    linked(line.id) { compactRow(line) }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Large — the full glance

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent.gradient)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Text(String(snapshot.profileName.prefix(1)))
                            .font(theme.typography.label.weight(.bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.profileName)
                        .font(theme.typography.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(snapshot.headline)
                        .font(theme.typography.micro)
                        .foregroundStyle(theme.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(accent)
                    Text("\(snapshot.loginStreak)")
                        .font(theme.typography.heading)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                }
            }

            // Streak chain — seven pips, the last being today.
            HStack(spacing: 4) {
                ForEach(Array(snapshot.recentLoginFlags.enumerated()), id: \.offset) { _, active in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(active ? accent : theme.gridline)
                        .frame(height: 5)
                }
            }

            Divider().overlay(theme.gridline)

            VStack(spacing: 11) {
                ForEach(snapshot.lines.prefix(5)) { line in
                    linked(line.id) { fullRow(line) }
                }
            }

            Spacer(minLength: 0)

            Text("Updated \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9))
                .foregroundStyle(theme.textMuted)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Rows

    /// Ring data for the medium widget, worst-status first so the ring that needs
    /// attention is the outer (largest) one.
    private func rings(limit: Int) -> [RingData] {
        snapshot.lines.prefix(limit).map { line in
            RingData(
                id: line.id,
                label: line.title,
                fraction: line.fraction,
                colorHex: line.colorHex,
                symbolName: line.symbolName,
                valueText: line.progressText,
                status: line.status
            )
        }
    }

    private func compactRow(_ line: WidgetTrackerLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: line.symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(hex: line.colorHex))
                Text(line.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Formatters.percent(min(line.fraction, 1)))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textMuted)
            }
            MiniProgressBar(
                fraction: line.fraction,
                status: line.status,
                color: Color(hex: line.colorHex),
                height: 4,
                breachesLimit: line.breachesLimit
            )
        }
    }

    private func fullRow(_ line: WidgetTrackerLine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: line.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: line.colorHex))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(line.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if line.streak > 1 {
                        // SF Symbol rather than an emoji: emoji render at the
                        // system's whim, ignore the text colour, and don't respect
                        // the weight of the type around them.
                        Label("\(line.streak)", systemImage: "flame.fill")
                            .font(.system(size: 10, weight: .medium))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(theme.textMuted)
                    }
                    Text(line.progressText)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                MiniProgressBar(
                    fraction: line.fraction,
                    status: line.status,
                    color: Color(hex: line.colorHex),
                    height: 5,
                    breachesLimit: line.breachesLimit
                )
            }

            if !line.recentValues.isEmpty {
                SparklineView(
                    values: line.recentValues,
                    color: Color(hex: line.colorHex),
                    style: .bars,
                    lineWidth: 1.5
                )
                .frame(width: 42, height: 20)
            }
        }
    }

    private var emptyLine: some View {
        VStack(spacing: 4) {
            Image(systemName: "target")
                .font(.title3)
                .foregroundStyle(theme.textMuted)
            Text("No goals yet")
                .font(theme.typography.micro)
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WidgetPreviewTile

/// A widget rendered at true size on a home-screen-ish plate. Lets the demo app
/// and a design review see the widgets without installing an extension.
public struct WidgetPreviewTile: View {
    @Environment(\.trackerTheme) private var theme

    private let snapshot: WidgetSnapshot
    private let size: TrackerWidgetSize
    private let linksToTrackers: Bool

    /// - Parameter linksToTrackers: wraps each row in a deep link so a tap lands
    ///   on that tracker rather than the dashboard. Off for previews and the
    ///   in-app gallery, where a `Link` would be inert or actively confusing.
    public init(
        snapshot: WidgetSnapshot,
        size: TrackerWidgetSize,
        linksToTrackers: Bool = false
    ) {
        self.snapshot = snapshot
        self.size = size
        self.linksToTrackers = linksToTrackers
    }

    /// Wraps a row in a deep link when links are enabled.
    @ViewBuilder
    private func linked<Content: View>(
        _ id: UUID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if linksToTrackers {
            Link(destination: WidgetDeepLink.tracker(id).url) { content() }
        } else {
            content()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(size.displayName)
                .font(theme.typography.label.weight(.semibold))
                .foregroundStyle(theme.textMuted)

            TrackerWidgetView(snapshot: snapshot, size: size)
                .frame(width: size.previewSize.width, height: size.previewSize.height)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
    }
}

#Preview("Widgets") {
    ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(TrackerWidgetSize.allCases, id: \.self) { size in
                WidgetPreviewTile(snapshot: .placeholder, size: size)
            }
        }
        .padding()
    }
    .background(ChartPalette.standard.chrome.plane.color)
}
