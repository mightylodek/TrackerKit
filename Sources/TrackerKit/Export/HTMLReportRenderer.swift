import Foundation

/// A self-contained HTML report — no external CSS, no fonts, no scripts, no
/// network. Mail clients strip most of what a web page can do, so everything here
/// is inline-safe markup and plain CSS custom properties.
///
/// Accessibility is built in rather than bolted on: every status carries a glyph
/// **and** a word, sparklines have `<title>` elements, and a full data table sits
/// at the bottom so nothing is readable only as a picture.
public struct HTMLReportRenderer: ReportRendering {
    public var format: ReportFormat { .html }
    /// Include the per-tracker sparkline SVGs.
    public var includeSparklines: Bool
    /// Include the full data table at the end.
    public var includeTable: Bool

    public init(includeSparklines: Bool = true, includeTable: Bool = true) {
        self.includeSparklines = includeSparklines
        self.includeTable = includeTable
    }

    public func render(_ report: ProgressReport) -> Data {
        Data(html(report).utf8)
    }

    // MARK: Document

    public func html(_ report: ProgressReport) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(report.title))</title>
        <style>\(stylesheet)</style>
        </head>
        <body>
        <div class="wrap">
        \(headerBlock(report))
        \(summaryBlock(report))
        \(itemsBlock(report))
        \(goalChangeBlock(report))
        \(includeTable ? tableBlock(report) : "")
        <p class="footer">Generated \(escape(report.generatedAt.formatted(date: .abbreviated, time: .shortened))) by TrackerKit.</p>
        </div>
        </body>
        </html>
        """
    }

    // MARK: Blocks

    private func headerBlock(_ report: ProgressReport) -> String {
        """
        <header class="head">
          <p class="eyebrow">Progress report</p>
          <h1>\(escape(report.profileName))</h1>
          <p class="range">\(escape(report.rangeText))</p>
        </header>
        """
    }

    private func summaryBlock(_ report: ProgressReport) -> String {
        let streakNote = report.loginStreak.isPersonalBest && report.loginStreak.current > 1
            ? "personal best"
            : "longest \(report.loginStreak.longest)"

        return """
        <section class="stats">
          <div class="stat">
            <p class="stat-value">\(report.loginStreak.current)</p>
            <p class="stat-label">Day streak</p>
            <p class="stat-sub">\(escape(streakNote))</p>
          </div>
          <div class="stat">
            <p class="stat-value">\(report.greenCount)<span class="stat-of">/\(report.scoredItems.count)</span></p>
            <p class="stat-label">On track</p>
            <p class="stat-sub">\(Formatters.percent(report.greenShare)) of goals</p>
          </div>
          <div class="stat">
            <p class="stat-value">\(report.yellowCount)</p>
            <p class="stat-label">At risk</p>
            <p class="stat-sub">needs a push</p>
          </div>
          <div class="stat">
            <p class="stat-value">\(report.redCount)</p>
            <p class="stat-label">Off track</p>
            <p class="stat-sub">missed the mark</p>
          </div>
        </section>
        <p class="headline">\(escape(report.headline))</p>
        """
    }

    private func itemsBlock(_ report: ProgressReport) -> String {
        guard !report.items.isEmpty else {
            return #"<p class="empty">No trackers on this profile yet.</p>"#
        }

        let cards = report.items.map { item -> String in
            let fraction = min(max(item.completionFraction ?? 0, 0), 1)
            let overflow = (item.completionFraction ?? 0) > 1

            let trendMarkup: String
            if let trend = item.trend {
                let favorable = trend.isFavorable(for: item.goal?.direction ?? .atLeast)
                let arrow = trend.direction == .rising ? "▲" : (trend.direction == .falling ? "▼" : "▬")
                trendMarkup = """
                <span class="trend \(favorable ? "good" : "bad")">\(arrow) \(escape(trend.displayText(unit: item.unit)))</span>
                """
            } else {
                trendMarkup = #"<span class="trend flat">— no comparison</span>"#
            }

            let streakMarkup = item.streak.current > 0
                ? #"<span class="chip">🔥 \#(item.streak.current) in a row</span>"#
                : ""

            let goalFlag = item.goalChangedInWindow
                ? #"<span class="chip warn">⚑ goal changed</span>"#
                : ""

            return """
            <article class="card">
              <div class="card-head">
                <div>
                  <h2>\(escape(item.title))</h2>
                  <p class="goal">\(escape(item.goal?.summary ?? "No goal set"))</p>
                </div>
                \(statusPill(item.status))
              </div>
              <p class="value">\(escape(item.progressText))</p>
              <div class="bar" role="img" aria-label="\(escape(item.progressText)) — \(escape(item.status.displayName))">
                <div class="bar-fill \(statusClass(item.status))" style="width:\(Int(fraction * 100))%"></div>
                \(overflow ? #"<span class="over">over</span>"# : "")
              </div>
              <p class="reason">\(escape(item.statusReason))</p>
              <p class="meta">\(trendMarkup) \(streakMarkup) \(goalFlag)</p>
              \(includeSparklines ? sparkline(item) : "")
            </article>
            """
        }

        return #"<section class="cards">"# + cards.joined(separator: "\n") + "</section>"
    }

    private func goalChangeBlock(_ report: ProgressReport) -> String {
        let changed = report.items.filter(\.goalChangedInWindow)
        guard !changed.isEmpty else { return "" }

        let rows = changed.map { item in
            let note = item.goal?.note.map { " — \(escape($0))" } ?? ""
            return "<li><strong>\(escape(item.title))</strong> → \(escape(item.goal?.summary ?? "—"))\(note)</li>"
        }.joined(separator: "\n")

        return """
        <section class="notice">
          <h3>⚑ Goals changed during this period</h3>
          <p>These targets moved inside the window. Week-over-week comparisons are against a moving goalpost.</p>
          <ul>\(rows)</ul>
        </section>
        """
    }

    private func tableBlock(_ report: ProgressReport) -> String {
        let rows = report.items.map { item in
            """
            <tr>
              <td>\(escape(item.title))</td>
              <td class="num">\(escape(item.actualText))</td>
              <td class="num">\(escape(item.targetText ?? "—"))</td>
              <td>\(statusGlyph(item.status)) \(escape(item.status.displayName))</td>
              <td class="num">\(escape(item.trend?.displayText(unit: item.unit) ?? "—"))</td>
              <td class="num">\(item.streak.current)</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <section class="table-wrap">
          <h3>All figures</h3>
          <table>
            <thead>
              <tr><th>Tracker</th><th class="num">Actual</th><th class="num">Target</th><th>Status</th><th class="num">Change</th><th class="num">Streak</th></tr>
            </thead>
            <tbody>\(rows)</tbody>
          </table>
        </section>
        """
    }

    // MARK: Sparkline

    /// A bar sparkline as inline SVG. No script, no library — it renders in Mail,
    /// Quick Look and any browser.
    private func sparkline(_ item: ReportItem) -> String {
        let values = item.dailyValues
        guard values.count > 1 else { return "" }

        let width = 280.0
        let height = 44.0
        let gap = 2.0
        let barWidth = max(2.0, (width - gap * Double(values.count - 1)) / Double(values.count))
        let maxValue = max(values.map(\.value).max() ?? 1, 0.0001)

        let bars = values.enumerated().map { index, day -> String in
            let barHeight = max(1.5, (day.value / maxValue) * (height - 6))
            let x = Double(index) * (barWidth + gap)
            let y = height - barHeight
            let opacity = day.hasData ? "1" : "0.25"
            return #"<rect x="\#(round(x * 10) / 10)" y="\#(round(y * 10) / 10)" width="\#(round(barWidth * 10) / 10)" height="\#(round(barHeight * 10) / 10)" rx="2" fill="\#(item.colorHex)" opacity="\#(opacity)"></rect>"#
        }.joined()

        let first = values.first.map { Formatters.dayMonth($0.date) } ?? ""
        let last = values.last.map { Formatters.dayMonth($0.date) } ?? ""

        return """
        <figure class="spark">
          <svg viewBox="0 0 \(Int(width)) \(Int(height))" width="100%" height="\(Int(height))" preserveAspectRatio="none" role="img" aria-label="Daily values for \(escape(item.title))">
            <title>Daily values for \(escape(item.title))</title>
            \(bars)
          </svg>
          <figcaption><span>\(escape(first))</span><span>\(escape(last))</span></figcaption>
        </figure>
        """
    }

    // MARK: Status

    private func statusPill(_ status: StoplightStatus) -> String {
        """
        <span class="pill \(statusClass(status))">\(statusGlyph(status)) \(escape(status.displayName))</span>
        """
    }

    private func statusClass(_ status: StoplightStatus) -> String {
        switch status {
        case .green: "ok"
        case .yellow: "warn"
        case .red: "bad"
        case .neutral: "none"
        }
    }

    /// A glyph alongside the word — status is never carried by color alone.
    private func statusGlyph(_ status: StoplightStatus) -> String {
        switch status {
        case .green: "●"
        case .yellow: "▲"
        case .red: "■"
        case .neutral: "○"
        }
    }

    // MARK: Escaping

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: Stylesheet

    /// Values come from the same validated palette the in-app charts use, so a
    /// printed report and the screen agree.
    private var stylesheet: String {
        """
        :root {
          color-scheme: light dark;
          --surface: #fcfcfb;
          --plane: #f9f9f7;
          --ink: #0b0b0b;
          --ink-2: #52514e;
          --muted: #898781;
          --grid: #e1e0d9;
          --good: #0ca30c;
          --warn: #fab219;
          --bad: #d03b3b;
          --up: #006300;
          --down: #d03b3b;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --surface: #1a1a19;
            --plane: #0d0d0d;
            --ink: #ffffff;
            --ink-2: #c3c2b7;
            --muted: #898781;
            --grid: #2c2c2a;
            --up: #0ca30c;
            --down: #e66767;
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          padding: 24px 16px 48px;
          background: var(--plane);
          color: var(--ink);
          font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif;
          -webkit-text-size-adjust: 100%;
        }
        .wrap { max-width: 680px; margin: 0 auto; }
        .head { margin-bottom: 20px; }
        .eyebrow { margin: 0; font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
        h1 { margin: 4px 0 2px; font-size: 30px; line-height: 1.15; }
        .range { margin: 0; color: var(--ink-2); }
        .stats { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; }
        .stat {
          flex: 1 1 120px; padding: 12px 14px; background: var(--surface);
          border: 1px solid var(--grid); border-radius: 14px;
        }
        .stat-value { margin: 0; font-size: 28px; font-weight: 640; line-height: 1.1; }
        .stat-of { font-size: 16px; color: var(--muted); font-weight: 500; }
        .stat-label { margin: 2px 0 0; font-size: 13px; color: var(--ink-2); }
        .stat-sub { margin: 1px 0 0; font-size: 12px; color: var(--muted); }
        .headline { margin: 0 0 22px; font-size: 17px; color: var(--ink-2); }
        .cards { display: grid; gap: 12px; }
        .card { background: var(--surface); border: 1px solid var(--grid); border-radius: 16px; padding: 16px; }
        .card-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; }
        .card h2 { margin: 0; font-size: 17px; }
        .goal { margin: 2px 0 0; font-size: 13px; color: var(--muted); }
        .value { margin: 12px 0 8px; font-size: 24px; font-weight: 640; }
        .bar { position: relative; height: 10px; background: var(--grid); border-radius: 5px; overflow: hidden; }
        .bar-fill { height: 100%; border-radius: 5px; }
        .bar-fill.ok { background: var(--good); }
        .bar-fill.warn { background: var(--warn); }
        .bar-fill.bad { background: var(--bad); }
        .bar-fill.none { background: var(--muted); }
        .over { position: absolute; right: 6px; top: -4px; font-size: 10px; color: var(--surface); font-weight: 700; }
        .reason { margin: 8px 0 0; font-size: 14px; color: var(--ink-2); }
        .meta { margin: 8px 0 0; font-size: 13px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
        .pill { flex: none; font-size: 12px; font-weight: 640; padding: 4px 10px; border-radius: 999px; border: 1px solid var(--grid); white-space: nowrap; }
        .pill.ok { color: var(--good); }
        .pill.warn { color: #9a6c00; }
        .pill.bad { color: var(--bad); }
        .pill.none { color: var(--muted); }
        .chip { font-size: 12px; color: var(--ink-2); background: var(--plane); border: 1px solid var(--grid); border-radius: 999px; padding: 3px 9px; }
        .chip.warn { color: #9a6c00; }
        .trend { font-weight: 600; }
        .trend.good { color: var(--up); }
        .trend.bad { color: var(--down); }
        .trend.flat { color: var(--muted); font-weight: 400; }
        .spark { margin: 14px 0 0; }
        .spark svg { display: block; }
        .spark figcaption { display: flex; justify-content: space-between; font-size: 11px; color: var(--muted); margin-top: 4px; }
        .notice { margin-top: 20px; padding: 14px 16px; border: 1px solid var(--warn); border-radius: 14px; background: var(--surface); }
        .notice h3 { margin: 0 0 6px; font-size: 15px; }
        .notice p { margin: 0 0 8px; font-size: 14px; color: var(--ink-2); }
        .notice ul { margin: 0; padding-left: 18px; font-size: 14px; }
        .table-wrap { margin-top: 24px; }
        .table-wrap h3 { font-size: 15px; margin: 0 0 8px; }
        table { width: 100%; border-collapse: collapse; font-size: 14px; background: var(--surface); border: 1px solid var(--grid); border-radius: 12px; overflow: hidden; }
        th, td { text-align: left; padding: 9px 12px; border-bottom: 1px solid var(--grid); }
        th { font-size: 12px; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); font-weight: 600; }
        tr:last-child td { border-bottom: 0; }
        .num { text-align: right; font-variant-numeric: tabular-nums; }
        .empty { color: var(--muted); font-style: italic; }
        .footer { margin-top: 28px; font-size: 12px; color: var(--muted); text-align: center; }
        """
    }
}
