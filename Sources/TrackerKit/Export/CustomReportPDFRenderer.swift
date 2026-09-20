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
@MainActor
public struct CustomReportPDFRenderer {

    /// US Letter at 72dpi, matching the existing report renderer.
    public static let pageSize = CGSize(width: 612, height: 792)
    public static let margin: CGFloat = 36

    public var scale: CGFloat

    public init(scale: CGFloat = 2) {
        self.scale = scale
    }

    public func render(_ report: CustomReport, theme: TrackerTheme = .nocturne) -> Data {
        let contentWidth = Self.pageSize.width - Self.margin * 2

        let document = CustomReportDocumentView(report: report)
            .trackerTheme(theme)
            .frame(width: contentWidth)
            .background(theme.plane)

        let renderer = ImageRenderer(content: document)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)

        guard let image = renderer.uiImage, image.size.height > 0 else { return Data() }

        let usableHeight = Self.pageSize.height - Self.margin * 2
        let pageCount = max(1, Int(ceil(image.size.height / usableHeight)))

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for page in 0..<pageCount {
            context.beginPDFPage(nil)

            // Paint the page ground first: a transparent PDF page prints as
            // white, which turns a dark theme's light text invisible on paper.
            context.setFillColor(UIColor(theme.plane).cgColor)
            context.fill(mediaBox)

            let offset = CGFloat(page) * usableHeight
            let sliceHeight = min(usableHeight, image.size.height - offset)

            if let slice = crop(image, y: offset, height: sliceHeight) {
                // Flip: Core Graphics' PDF origin is bottom-left, UIImage's is
                // top-left. Without this every page draws upside down.
                context.saveGState()
                context.translateBy(x: 0, y: Self.pageSize.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(
                    slice,
                    in: CGRect(
                        x: Self.margin,
                        y: Self.margin,
                        width: Self.pageSize.width - Self.margin * 2,
                        height: sliceHeight
                    )
                )
                context.restoreGState()
            }

            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    /// Writes to a temporary file and returns the URL, for sharing or attaching.
    public func write(
        _ report: CustomReport,
        theme: TrackerTheme = .nocturne,
        to directory: URL? = nil
    ) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        let safeName = report.definition.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stem = safeName.isEmpty ? "report" : safeName
        let url = folder.appendingPathComponent("\(stem)-\(Formatters.fileStamp()).pdf")
        try render(report, theme: theme).write(to: url, options: .atomic)
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

// MARK: - CustomReportDocumentView

/// The report laid out for paper: charts, then the numbers.
///
/// Separate from ``CustomReportView`` because a page is not a screen — no
/// navigation chrome, no scroll view, and the header repeats information a
/// reader who wasn't there needs.
struct CustomReportDocumentView: View {
    @Environment(\.trackerTheme) private var theme

    let report: CustomReport

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(report.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Text(report.rangeText)
                    .font(theme.typography.heading)
                    .foregroundStyle(theme.textSecondary)
                Text(subtitle)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textMuted)
            }

            if !report.definition.visuals.isEmpty {
                ReportVisualsView(report: report, isPaged: true)
            }

            ForEach(report.trackers) { tracker in
                ReportTrackerTable(tracker: tracker)
            }
        }
        .padding(theme.spacing.md)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(report.trackers.map(\.title).joined(separator: ", "))
        if let days = report.definition.weekdaySummary { parts.append(days) }
        if report.definition.breakdowns.contains(.weekly) {
            parts.append("weeks from \(report.definition.weekStartName)")
        }
        parts.append("generated \(Formatters.dayMonth(report.generatedAt))")
        return parts.joined(separator: " · ")
    }
}

#endif
