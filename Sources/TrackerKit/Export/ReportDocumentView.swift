import SwiftUI

/// The printable/shareable rendering of a report.
///
/// Shares the charts with the app rather than redrawing them for print, so a PDF
/// emailed to a coach looks like what the kid saw on screen. Laid out to US Letter
/// width and paginated by item count, so nothing is ever sliced mid-row.
public struct ReportDocumentView: View {
    @Environment(\.trackerTheme) private var theme

    private let report: ProgressReport
    private let pageIndex: Int
    private let pageCount: Int
    private let items: [ReportItem]

    /// US Letter at 72dpi.
    public static let pageSize = CGSize(width: 612, height: 792)
    /// Items per page. Tuned so a full page never overflows its height.
    public static let itemsPerPage = 4

    public init(report: ProgressReport, pageIndex: Int = 0, pageCount: Int = 1) {
        self.report = report
        self.pageIndex = pageIndex
        self.pageCount = pageCount

        let start = pageIndex * Self.itemsPerPage
        let end = min(start + Self.itemsPerPage, report.items.count)
        self.items = start < end ? Array(report.items[start..<end]) : []
    }

    /// How many pages this report needs.
    public static func pageCount(for report: ProgressReport) -> Int {
        max(1, Int(ceil(Double(report.items.count) / Double(itemsPerPage))))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if pageIndex == 0 {
                header
                statRow
            } else {
                continuationHeader
            }

            VStack(spacing: 14) {
                ForEach(items) { item in
                    itemBlock(item)
                }
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(40)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(theme.surface)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROGRESS REPORT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(theme.textMuted)

            Text(report.profileName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(theme.textPrimary)

            Text(report.rangeText)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)

            Text(report.headline)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 6)
        }
    }

    private var continuationHeader: some View {
        HStack {
            Text(report.profileName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("·")
                .foregroundStyle(theme.textMuted)
            Text(report.rangeText)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text("continued")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.gridline).frame(height: 1)
        }
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: 10) {
            statTile(
                value: "\(report.loginStreak.current)",
                label: "Day streak",
                sub: "best \(report.loginStreak.longest)"
            )
            statTile(
                value: "\(report.greenCount)",
                label: "On track",
                sub: "of \(report.scoredItems.count) goals"
            )
            statTile(
                value: "\(report.yellowCount)",
                label: "At risk",
                sub: "needs a push"
            )
            statTile(
                value: "\(report.redCount)",
                label: "Off track",
                sub: "missed"
            )
        }
    }

    private func statTile(value: String, label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.plane, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(theme.gridline, lineWidth: 1)
        }
    }

    // MARK: Item

    private func itemBlock(_ item: ReportItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: item.colorHex))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(hex: item.colorHex).opacity(0.14)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(item.goal?.summary ?? "No goal set")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.progressText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.textPrimary)

                    HStack(spacing: 4) {
                        Image(systemName: item.status.symbolName)
                            .font(.system(size: 9))
                        Text(item.status.displayName)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(theme.statusColor(item.status))
                }
            }

            if item.target != nil {
                BulletChartView(
                    actual: item.actual,
                    target: item.target,
                    unit: item.unit,
                    status: item.status,
                    direction: item.goal?.direction ?? .atLeast,
                    barHeight: 11,
                    showsValue: false
                )
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.statusReason)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)

                    HStack(spacing: 8) {
                        if let trend = item.trend {
                            Text("Change \(trend.displayText(unit: item.unit))")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.textMuted)
                        }
                        if item.streak.current > 0 {
                            Text("\(item.streak.current) in a row")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.textMuted)
                        }
                        if item.goalChangedInWindow {
                            Text("goal changed this period")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.statusColor(.yellow))
                        }
                    }
                }

                Spacer()

                if item.dailyValues.count > 1 {
                    SparklineView(
                        dailyValues: item.dailyValues,
                        color: Color(hex: item.colorHex),
                        style: .bars
                    )
                    .frame(width: 96, height: 26)
                }
            }
        }
        .padding(12)
        .background(theme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(theme.gridline, lineWidth: 1)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            Spacer()
            if pageCount > 1 {
                Text("Page \(pageIndex + 1) of \(pageCount)")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(theme.textMuted)
    }
}

#Preview("Report page") {
    let store = TrackerStore.preview()
    let report = store.buildReport(lookbackDays: 7)!

    return ScrollView {
        ReportDocumentView(report: report, pageIndex: 0, pageCount: 2)
            .border(Color.gray.opacity(0.3))
    }
}
