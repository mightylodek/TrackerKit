#if os(iOS)

import SwiftUI
import UIKit

// MARK: - CustomReportPDFRenderer

/// Renders a custom report — charts and tables — to a PDF.
///
/// `@MainActor` because `ImageRenderer` is.
///
/// Pagination works by rendering the whole report once at page width with
/// unbounded height, then slicing that image into page-sized bands. Hand-built
/// SwiftUI pagination would need every view to report its own height and split
/// cleanly, which charts do not; slicing is dumber and handles arbitrary content
/// without ever cutting a page short.
///
/// Drawing goes through `UIGraphicsPDFRenderer` rather than a raw `CGContext`.
/// A bare CGContext PDF has its origin bottom-left while `UIImage` has it
/// top-left, and reconciling that by hand produced pages that printed rotated
/// 180°. `UIGraphicsPDFRenderer` works in UIKit coordinates, so `draw(in:)`
/// means what it looks like it means.
@MainActor
public struct CustomReportPDFRenderer {

    /// US Letter at 72dpi, matching the existing report renderer.
    public static let pageSize = CGSize(width: 612, height: 792)
    public static let landscapePageSize = CGSize(width: 792, height: 612)
    public static let margin: CGFloat = 36

    /// Which way round the paper goes.
    public enum Orientation: String, Sendable, CaseIterable, Hashable {
        case portrait
        case landscape

        public var size: CGSize {
            self == .portrait ? pageSize : landscapePageSize
        }

        public var displayName: String {
            self == .portrait ? "Portrait" : "Landscape"
        }
    }

    /// Landscape once there is more than one row to fill.
    ///
    /// Four tiles across a landscape sheet get a sensible aspect each; the same
    /// four stacked down a portrait one squeeze into letterbox strips.
    public static func suggestedOrientation(for report: CustomReport) -> Orientation {
        report.pageTileCount > 2 ? .landscape : .portrait
    }

    /// Grid shape per page.
    ///
    /// Chosen so whole rows fit the sheet with the header above them, which is
    /// what lets pages be built tile by tile instead of sliced.
    static func grid(for orientation: Orientation) -> (columns: Int, rows: Int, tileHeight: CGFloat) {
        switch orientation {
        case .portrait: (2, 2, 300)
        case .landscape: (3, 2, 240)
        }
    }

    /// The theme a report prints in.
    ///
    /// Nocturne is a dark-first identity, and a dark page is the right call on
    /// screen and the wrong one on paper — it prints a near-black ground across
    /// every sheet. Print defaults to the light theme; the app's own look is
    /// available for anyone exporting to read on a screen.
    public enum Appearance: String, Sendable, CaseIterable, Hashable {
        case light
        case matchApp

        public var displayName: String {
            switch self {
            case .light: "Light — best for printing"
            case .matchApp: "Match the app"
            }
        }

        public var detail: String {
            switch self {
            case .light: "White background, dark text. Uses far less ink."
            case .matchApp: "The dark theme you see on screen."
            }
        }
    }

    public var scale: CGFloat

    public init(scale: CGFloat = 2) {
        self.scale = scale
    }

    /// Renders in the appearance chosen for this export.
    public func render(
        _ report: CustomReport,
        appearance: Appearance,
        appTheme: TrackerTheme,
        orientation: Orientation? = nil
    ) -> Data {
        let page = orientation ?? Self.suggestedOrientation(for: report)
        switch appearance {
        case .light:
            return render(report, theme: .standard, colorScheme: .light, orientation: page)
        case .matchApp:
            return render(
                report,
                theme: appTheme,
                colorScheme: appTheme.preferredColorScheme ?? .light,
                orientation: page
            )
        }
    }

    public func render(
        _ report: CustomReport,
        theme: TrackerTheme = .standard,
        colorScheme: ColorScheme = .light,
        orientation: Orientation = .portrait
    ) -> Data {
        let pageSize = orientation.size
        let bounds = CGRect(origin: .zero, size: pageSize)
        let contentWidth = pageSize.width - Self.margin * 2
        let contentHeight = pageSize.height - Self.margin * 2
        let shape = Self.grid(for: orientation)
        let pages = report.pageTiles(perPage: shape.columns * shape.rows)

        // Resolve the ground once, against the appearance being drawn, rather
        // than letting a dynamic colour pick the device's.
        let ground = UIColor(theme.plane).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        )

        let pdf = UIGraphicsPDFRenderer(bounds: bounds)
        return pdf.pdfData { context in
            // A report with nothing in it still owes the reader a sheet.
            guard !pages.isEmpty else {
                context.beginPage()
                ground.setFill()
                context.fill(bounds)
                return
            }

            for (index, tiles) in pages.enumerated() {
                context.beginPage()
                ground.setFill()
                context.fill(bounds)

                let page = CustomReportPageView(
                    report: report,
                    tiles: tiles,
                    columns: shape.columns,
                    tileHeight: shape.tileHeight,
                    pageNumber: index + 1,
                    pageCount: pages.count
                )
                .trackerTheme(theme)
                .environment(\.colorScheme, colorScheme)
                .frame(width: contentWidth)

                let renderer = ImageRenderer(content: page)
                renderer.scale = scale
                renderer.proposedSize = ProposedViewSize(width: contentWidth, height: contentHeight)

                guard let image = renderer.uiImage else { continue }
                image.draw(in: CGRect(
                    x: Self.margin,
                    y: Self.margin,
                    width: contentWidth,
                    height: min(image.size.height, contentHeight)
                ))
            }
        }
    }

    /// Slices a tall image across PDF pages.
    ///
    /// Split out from `render` so a test can feed it an image whose corners are
    /// known and check where they land. Orientation is exactly the kind of thing
    /// that looks fine in a thumbnail and comes out of a printer upside down.
    func paginate(_ image: UIImage, ground: UIColor, pageSize: CGSize = CustomReportPDFRenderer.pageSize) -> Data {
        let usableHeight = pageSize.height - Self.margin * 2
        let pageCount = max(1, Int(ceil(image.size.height / usableHeight)))
        let bounds = CGRect(origin: .zero, size: pageSize)

        let pdf = UIGraphicsPDFRenderer(bounds: bounds)
        return pdf.pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()

                // A transparent PDF page prints white, which would leave a dark
                // theme's light text invisible on paper.
                ground.setFill()
                context.fill(bounds)

                let offset = CGFloat(page) * usableHeight
                let sliceHeight = min(usableHeight, image.size.height - offset)
                guard sliceHeight > 0, let slice = crop(image, y: offset, height: sliceHeight) else {
                    continue
                }

                // UIImage draws the right way up here — no manual flip, which is
                // what produced 180°-rotated pages before.
                UIImage(cgImage: slice, scale: scale, orientation: .up).draw(
                    in: CGRect(
                        x: Self.margin,
                        y: Self.margin,
                        width: pageSize.width - Self.margin * 2,
                        height: sliceHeight
                    )
                )
            }
        }
    }

    /// Writes to a temporary file and returns the URL, for sharing or attaching.
    public func write(
        _ report: CustomReport,
        appearance: Appearance = .light,
        appTheme: TrackerTheme = .nocturne,
        orientation: Orientation? = nil,
        to directory: URL? = nil
    ) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        let safeName = report.definition.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stem = safeName.isEmpty ? "report" : safeName
        let url = folder.appendingPathComponent("\(stem)-\(Formatters.fileStamp()).pdf")
        try render(report, appearance: appearance, appTheme: appTheme, orientation: orientation)
            .write(to: url, options: .atomic)
        return url
    }

    private func crop(_ image: UIImage, y: CGFloat, height: CGFloat) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let pixelScale = CGFloat(cgImage.height) / image.size.height
        let rect = CGRect(
            x: 0,
            y: y * pixelScale,
            width: CGFloat(cgImage.width),
            height: height * pixelScale
        )
        return cgImage.cropping(to: rect)
    }
}

// MARK: - CustomReportPageView

/// One sheet: a one-line masthead and a grid of tiles.
///
/// Separate from ``CustomReportView`` because a page is not a screen — no
/// navigation chrome, no scrolling, and a header that repeats what a reader who
/// wasn't there needs to know, in one line rather than three.
struct CustomReportPageView: View {
    @Environment(\.trackerTheme) private var theme

    /// Height a ``TrackerCard`` adds around its content: title, subtitle, card
    /// padding, and the few points of clearance the plot's top axis label needs.
    ///
    /// Measured, not guessed — and guarded by a test, because the last four
    /// points of it arrived with a `.padding(.top)` that pushed every chart tile
    /// past its cell and into the row below.
    static let cardChrome: CGFloat = 94

    let report: CustomReport
    let tiles: [ReportPageTile]
    let columns: Int
    let tileHeight: CGFloat
    let pageNumber: Int
    let pageCount: Int

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: theme.spacing.sm, alignment: .top),
            count: max(1, columns)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            header

            LazyVGrid(columns: gridColumns, spacing: theme.spacing.sm) {
                ForEach(tiles) { tile in
                    view(for: tile)
                        .frame(height: tileHeight)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
            Text(report.title)
                .font(theme.typography.heading)
                .foregroundStyle(theme.textPrimary)
            Text(report.rangeText)
                .font(theme.typography.label)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: theme.spacing.sm)
            Text(subtitle)
                .font(theme.typography.micro)
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func view(for tile: ReportPageTile) -> some View {
        switch tile {
        case .chart(let chart):
            // 90pt of card chrome above the plot — title, subtitle and padding,
            // measured rather than guessed at.
            ReportChartTileView(report: report, tile: chart, chartHeight: tileHeight - Self.cardChrome)
        case .numbers(let trackerID):
            if let tracker = report.tracker(trackerID) {
                ReportTrackerTable(tracker: tracker, isCompact: true)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let days = report.definition.weekdaySummary { parts.append(days) }
        if report.definition.breakdowns.contains(.weekly) {
            parts.append("weeks from \(report.definition.weekStartName)")
        }
        parts.append(Formatters.dayMonth(report.generatedAt))
        if pageCount > 1 { parts.append("\(pageNumber)/\(pageCount)") }
        return parts.joined(separator: " · ")
    }
}

#endif
