import Foundation

// MARK: - ReportRendering

/// Turns a report into bytes for one format.
public protocol ReportRendering: Sendable {
    var format: ReportFormat { get }
    func render(_ report: ProgressReport) -> Data
}

public extension ReportRendering {
    /// Renders and writes to a temporary file, returning the URL to attach or share.
    func write(_ report: ProgressReport, to directory: URL? = nil) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        let url = folder.appendingPathComponent("\(report.fileStem).\(format.fileExtension)")
        try render(report).write(to: url, options: .atomic)
        return url
    }
}

// MARK: - CSV

/// Flat, spreadsheet-ready rows. One row per tracker per day, plus a summary
/// block — so the file is useful both for eyeballing and for pivoting.
public struct CSVReportRenderer: ReportRendering {
    public var format: ReportFormat { .csv }
    public var includeDailyRows: Bool

    public init(includeDailyRows: Bool = true) {
        self.includeDailyRows = includeDailyRows
    }

    public func render(_ report: ProgressReport) -> Data {
        var lines: [String] = []

        lines.append("# \(escape(report.title))")
        lines.append("# Generated,\(escape(report.generatedAt.formatted()))")
        lines.append("# Login streak,\(report.loginStreak.current)")
        lines.append("")

        lines.append([
            "Tracker", "Kind", "Goal", "Target", "Actual", "Unit",
            "Status", "Reason", "Change", "Streak", "Goal changed"
        ].joined(separator: ","))

        for item in report.items {
            lines.append([
                escape(item.title),
                item.kind.rawValue,
                escape(item.goal?.summary ?? "—"),
                item.target.map { Formatters.number($0) } ?? "",
                Formatters.number(item.actual),
                escape(item.unit),
                item.status.rawValue,
                escape(item.statusReason),
                escape(item.trend?.displayText(unit: item.unit) ?? ""),
                String(item.streak.current),
                item.goalChangedInWindow ? "yes" : "no"
            ].joined(separator: ","))
        }

        if includeDailyRows {
            lines.append("")
            lines.append("# Daily detail")
            lines.append(["Date", "Tracker", "Value", "Unit", "Entries"].joined(separator: ","))
            for item in report.items {
                for day in item.dailyValues {
                    lines.append([
                        Formatters.fileStamp(day.date),
                        escape(item.title),
                        Formatters.number(day.value),
                        escape(item.unit),
                        String(day.entryCount)
                    ].joined(separator: ","))
                }
            }
        }

        return Data(lines.joined(separator: "\n").utf8)
    }

    /// Quotes a field when it contains anything that would break the row.
    private func escape(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// MARK: - Markdown

/// Readable as plain text, so it doubles as the body of a text message.
public struct MarkdownReportRenderer: ReportRendering {
    public var format: ReportFormat { .markdown }
    /// Trims to the essentials — used for SMS, where length costs money and patience.
    public var compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func render(_ report: ProgressReport) -> Data {
        Data(text(report).utf8)
    }

    /// The rendered string, for dropping straight into a message body.
    public func text(_ report: ProgressReport) -> String {
        var lines: [String] = []

        if compact {
            lines.append("\(report.profileName) · \(report.rangeText)")
            lines.append(report.headline)
            if report.loginStreak.current > 0 {
                lines.append("Streak: \(report.loginStreak.displayText)")
            }
            lines.append("")
            for item in report.items.prefix(8) {
                lines.append("\(marker(item.status)) \(item.title): \(item.progressText)")
            }
            return lines.joined(separator: "\n")
        }

        lines.append("# \(report.title)")
        lines.append("")
        lines.append(report.headline)
        lines.append("")
        lines.append("- **Login streak:** \(report.loginStreak.displayText)"
            + (report.loginStreak.isPersonalBest && report.loginStreak.current > 1 ? " (personal best)" : ""))
        lines.append("- **On track:** \(report.greenCount) · **At risk:** \(report.yellowCount) · **Off track:** \(report.redCount)")
        lines.append("")

        lines.append("| Tracker | Progress | Goal | Status | Change | Streak |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for item in report.items {
            lines.append([
                "",
                item.title + (item.goalChangedInWindow ? " ⚑" : ""),
                item.progressText,
                item.goal?.summary ?? "—",
                "\(marker(item.status)) \(item.status.displayName)",
                item.trend?.displayText(unit: item.unit) ?? "—",
                item.streak.current > 0 ? "\(item.streak.current)" : "—",
                ""
            ].joined(separator: " | ").trimmingCharacters(in: .whitespaces))
        }
        lines.append("")

        if !report.attentionItems.isEmpty {
            lines.append("## Needs attention")
            for item in report.attentionItems {
                lines.append("- **\(item.title)** — \(item.statusReason)")
            }
            lines.append("")
        }

        if !report.winItems.isEmpty {
            lines.append("## Going well")
            for item in report.winItems.prefix(5) {
                let streakNote = item.streak.current > 1 ? " · \(item.streak.current) in a row" : ""
                lines.append("- **\(item.title)** — \(item.progressText)\(streakNote)")
            }
            lines.append("")
        }

        let changed = report.items.filter(\.goalChangedInWindow)
        if !changed.isEmpty {
            lines.append("## Goals changed this period")
            lines.append("")
            lines.append("These targets moved during the window, so compare with care.")
            lines.append("")
            for item in changed {
                lines.append("- **\(item.title)** → \(item.goal?.summary ?? "—")"
                    + (item.goal?.note.map { " (\($0))" } ?? ""))
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("_Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))_")

        return lines.joined(separator: "\n")
    }

    /// Text marker so status never rides on color alone.
    private func marker(_ status: StoplightStatus) -> String {
        switch status {
        case .green: "🟢"
        case .yellow: "🟡"
        case .red: "🔴"
        case .neutral: "⚪️"
        }
    }
}
