// iOS-only: UIGraphicsPDFRenderer and CGPDF rasterisation.
#if os(iOS)

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import TrackerKit

/// Which way up a printed page comes out.
///
/// Reported from a real printer: pages came out "backwards and upside down" —
/// a 180° rotation, from reconciling Core Graphics' bottom-left PDF origin with
/// UIImage's top-left one by hand. A thumbnail of a rotated page still looks
/// like a page, so this checks corners by pixel rather than by eye.
@Suite("PDF orientation")
@MainActor
struct PDFOrientationTests {

    /// A page-width image with one distinctly coloured corner.
    private func markedImage(height: CGFloat = 300) -> UIImage {
        let size = CGSize(width: CustomReportPDFRenderer.pageSize.width - 72, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Top-left quadrant only. In UIKit coordinates that is y = 0.
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
        }
    }

    /// Rasterises page 1 of a PDF, top-left origin.
    private func rasterise(_ data: Data) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1)
        else { return nil }

        let box = page.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: box.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: box.size))
            let ctx = context.cgContext
            // Flip into UIKit orientation so sampling matches what a reader sees.
            ctx.translateBy(x: 0, y: box.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.drawPDFPage(page)
        }
    }

    /// Samples one pixel, in a byte order this test defines rather than one the
    /// image happens to use.
    ///
    /// Reading `dataProvider` bytes directly assumes RGBA; a rasterised PDF page
    /// comes back BGRA, which silently turns every red sample into a blue one —
    /// an earlier draft of this test failed against perfectly upright pages for
    /// exactly that reason. Redrawing one pixel into a known context removes the
    /// assumption.
    private func colour(_ image: UIImage, atX x: CGFloat, y: CGFloat) -> (r: Int, g: Int, b: Int)? {
        guard let cg = image.cgImage else { return nil }
        let px = Int(x * CGFloat(cg.width))
        let py = Int(y * CGFloat(cg.height))
        guard px >= 0, py >= 0, px < cg.width, py < cg.height else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cg, in: CGRect(x: -CGFloat(px), y: -CGFloat(cg.height - py - 1),
                                    width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    private func isRed(_ c: (r: Int, g: Int, b: Int)?) -> Bool {
        guard let c else { return false }
        return c.r > 150 && c.g < 110 && c.b < 110
    }

    private func isWhite(_ c: (r: Int, g: Int, b: Int)?) -> Bool {
        guard let c else { return false }
        return c.r > 200 && c.g > 200 && c.b > 200
    }

    @Test("The marked corner lands top-left, not bottom-right")
    func orientationIsUpright() throws {
        let data = CustomReportPDFRenderer(scale: 1)
            .paginate(markedImage(), ground: .white)
        let page = try #require(rasterise(data), "Could not rasterise the PDF")

        // Sampled inside the marked quadrant, clear of the margins.
        #expect(isRed(colour(page, atX: 0.15, y: 0.10)),
                "Top-left is not the marked corner — the page is rotated or mirrored")
        #expect(isWhite(colour(page, atX: 0.85, y: 0.10)), "Top-right should be blank")
        #expect(isWhite(colour(page, atX: 0.15, y: 0.35)), "Bottom of the slice should be blank")
    }

    /// The specific failure: 180° puts the mark in the opposite corner.
    @Test("The page is not rotated 180°")
    func notRotated() throws {
        let data = CustomReportPDFRenderer(scale: 1)
            .paginate(markedImage(), ground: .white)
        let page = try #require(rasterise(data))

        #expect(!isRed(colour(page, atX: 0.85, y: 0.35)),
                "The mark landed bottom-right — the page is upside down and backwards")
    }

    @Test("Every page keeps the same orientation")
    func multiPageStaysUpright() throws {
        // Tall enough to need three pages.
        let tall = markedImage(height: 2_200)
        let data = CustomReportPDFRenderer(scale: 1).paginate(tall, ground: .white)

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages >= 3)

        // The mark spans the top half of a 2200pt image, so page 1 carries it.
        let page = try #require(rasterise(data))
        #expect(isRed(colour(page, atX: 0.15, y: 0.10)), "Page 1 is not upright")
    }

    // MARK: Print appearance

    @Test("Printing defaults to a light ground")
    func lightIsTheDefaultForPrint() {
        #expect(CustomReportPDFRenderer.Appearance.allCases.first == .light,
                "The first option offered should be the one that doesn't flood a page with ink")
    }

    /// A dark page costs a cartridge; the export has to actually honour the
    /// light choice rather than always drawing the app's theme.
    @Test("The light export really is light")
    func lightExportHasALightGround() throws {
        let renderer = CustomReportPDFRenderer(scale: 1)
        let light = renderer.paginate(markedImage(height: 120), ground: .white)
        let page = try #require(rasterise(light))

        // Below the drawn slice: bare page ground.
        #expect(isWhite(colour(page, atX: 0.5, y: 0.85)), "Page ground is not light")
    }

    @Test("A dark export still paints its ground rather than leaving it blank")
    func darkExportPaintsGround() throws {
        let renderer = CustomReportPDFRenderer(scale: 1)
        let dark = renderer.paginate(markedImage(height: 120), ground: UIColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 1))
        let page = try #require(rasterise(dark))

        #expect(!isWhite(colour(page, atX: 0.5, y: 0.85)),
                "A dark export left the page transparent, which prints white")
    }
}

#endif
