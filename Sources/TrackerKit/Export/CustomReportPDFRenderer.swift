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
    public static let margin: CGFloat = 36

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
    public func render(_ report: CustomReport, appearance: Appearance, appTheme: TrackerTheme) -> Data {
        switch appearance {
        case .light:
            return render(report, theme: .standard, colorScheme: .light)
        case .matchApp:
            return render(report, theme: appTheme, colorScheme: appTheme.preferredColorScheme ?? .light)
        }
    }

    public func render(
        _ report: CustomReport,
        theme: TrackerTheme = .standard,
        colorScheme: ColorScheme = .light
    ) -> Data {
        let contentWidth = Self.pageSize.width - Self.margin * 2

        let document = CustomReportDocumentView(report: report)
            .trackerTheme(theme)
            .environment(\.colorScheme, colorScheme)
            .frame(width: contentWidth)
            .background(theme.plane)

        let renderer = ImageRenderer(content: document)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)

        guard let image = renderer.uiImage, image.size.height > 0 else { return Data() }

        let usableHeight = Self.pageSize.height - Self.margin * 2
        let pageCount = max(1, Int(ceil(image.size.height / usableHeight)))
        let bounds = CGRect(origin: .zero, size: Self.pageSize)

        // Resolve the ground once, against the appearance being drawn, rather
        // than letting a dynamic colour pick the device's.
        let ground = UIColor(theme.plane).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        )

        return paginate(image, ground: ground)
    }

    /// Slices a tall image across PDF pages.
    ///
    /// Split out from `render` so a test can feed it an image whose corners are
    /// known and check where they land. Orientation is exactly the kind of thing
    /// that looks fine in a thumbnail and comes out of a printer upside down.
    func paginate(_ image: UIImage, ground: UIColor) -> Data {
        let usableHeight = Self.pageSize.height - Self.margin * 2
        let pageCount = max(1, Int(ceil(image.size.height / usableHeight)))
        let bounds = CGRect(origin: .zero, size: Self.pageSize)

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
                        width: Self.pageSize.width - Self.margin * 2,
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
        to directory: URL? = nil
    ) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        let safeName = report.definition.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stem = safeName.isEmpty ? "report" : safeName
        let url = folder.appendingPathComponent("\(stem)-\(Formatters.fileStamp()).pdf")
        try render(report, appearance: appearance, appTheme: appTheme).write(to: url, options: .atomic)
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
