import SwiftUI
import UIKit

/// Renders a report to a real, paginated PDF by drawing the SwiftUI
/// ``ReportDocumentView`` into a PDF context.
///
/// Pagination is by **item count, not by slicing a tall image** — slicing is the
/// obvious approach and it cuts rows in half across the page break. Each page is
/// its own laid-out view, so a tracker's block is always whole.
///
/// `@MainActor` because `ImageRenderer` is. That is why this type doesn't conform
/// to ``ReportRendering`` (whose `render` is nonisolated); use ``ExportComposer``
/// to dispatch across formats without caring about the difference.
@MainActor
public struct PDFReportRenderer {
    public var format: ReportFormat { .pdf }

    /// Rendering scale. 2 gives a crisp document without a huge file.
    public var scale: CGFloat

    public init(scale: CGFloat = 2) {
        self.scale = scale
    }

    /// Renders the whole report to PDF data.
    public func render(_ report: ProgressReport, theme: TrackerTheme = .standard) -> Data {
        let pageCount = ReportDocumentView.pageCount(for: report)
        let pageSize = ReportDocumentView.pageSize
        let bounds = CGRect(origin: .zero, size: pageSize)

        let data = NSMutableData()

        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = bounds
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        for pageIndex in 0..<pageCount {
            let page = ReportDocumentView(
                report: report,
                pageIndex: pageIndex,
                pageCount: pageCount
            )
            .trackerTheme(theme)

            let renderer = ImageRenderer(content: page)
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(pageSize)

            context.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(context)
            }
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    /// Renders and writes to a temporary file, returning the URL to attach or share.
    public func write(
        _ report: ProgressReport,
        theme: TrackerTheme = .standard,
        to directory: URL? = nil
    ) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        let url = folder.appendingPathComponent("\(report.fileStem).pdf")
        try render(report, theme: theme).write(to: url, options: .atomic)
        return url
    }

    /// A single-page PNG of the report's first page — handy for pasting into a
    /// message thread where a PDF attachment is overkill.
    public func renderPreviewImage(_ report: ProgressReport, theme: TrackerTheme = .standard) -> UIImage? {
        let page = ReportDocumentView(report: report, pageIndex: 0, pageCount: 1)
            .trackerTheme(theme)
        let renderer = ImageRenderer(content: page)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(ReportDocumentView.pageSize)
        return renderer.uiImage
    }
}

// MARK: - ExportComposer

/// One entry point that turns a report plus a format into a file on disk.
///
/// Hides the fact that PDF renders on the main actor and the text formats don't,
/// so callers pick a format and get a URL back either way.
@MainActor
public struct ExportComposer {

    public var theme: TrackerTheme

    public init(theme: TrackerTheme = .standard) {
        self.theme = theme
    }

    /// Renders `report` in `format` and returns a file URL in the temporary
    /// directory, ready to attach to mail, a message, or the share sheet.
    public func file(for report: ProgressReport, format: ReportFormat) throws -> URL {
        switch format {
        case .csv:
            return try CSVReportRenderer().write(report)
        case .markdown:
            return try MarkdownReportRenderer().write(report)
        case .html:
            return try HTMLReportRenderer().write(report)
        case .pdf:
            return try PDFReportRenderer().write(report, theme: theme)
        }
    }

    /// Raw bytes rather than a file, for a caller that wants to attach inline.
    public func data(for report: ProgressReport, format: ReportFormat) -> Data {
        switch format {
        case .csv: CSVReportRenderer().render(report)
        case .markdown: MarkdownReportRenderer().render(report)
        case .html: HTMLReportRenderer().render(report)
        case .pdf: PDFReportRenderer().render(report, theme: theme)
        }
    }

    /// Plain-text body for an email or message. Formats that are themselves text
    /// go inline; PDF and HTML get a short summary with the file attached.
    public func messageBody(for report: ProgressReport, format: ReportFormat) -> String {
        if format.isInlineText {
            return MarkdownReportRenderer(compact: true).text(report)
        }
        return """
        \(report.headline)

        \(report.rangeText)
        Login streak: \(report.loginStreak.displayText)

        Full report attached.
        """
    }

    /// Subject line for an email.
    public func subject(for report: ProgressReport) -> String {
        "\(report.profileName)'s progress — \(report.rangeText)"
    }

    /// Cleans up report files this composer wrote. Call after the composer
    /// dismisses so temporary reports don't pile up.
    public func cleanUp(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
