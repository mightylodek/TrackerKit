import SwiftUI

// MARK: - Nocturne palette

public extension ChartPalette {

    /// A committed dark identity.
    ///
    /// ## The idea
    /// **The app is one colour; colour means status.**
    ///
    /// Chrome, accents, rings and single-series charts all sit in one teal
    /// family against a cool near-black. The only other hues that ever appear are
    /// the reserved status colours — so anything green, amber or red on screen is
    /// *information*, never decoration. That single rule is what makes this read
    /// as designed rather than assembled, and it solves the brand-versus-status
    /// collision by construction instead of by convention.
    ///
    /// Teal was chosen partly for distance from the status palette: brand against
    /// status-good measures ΔE 23.0, comfortably clear, where an amber or a green
    /// brand would have impersonated a verdict.
    ///
    /// Multi-series charts still bring in the validated categorical palette —
    /// that is a correctness constraint, not a style choice, and it re-validates
    /// clean against this surface.
    static let nocturne: ChartPalette = {
        var palette = ChartPalette.standard

        palette.brand = BrandColors(
            accent: ColorPair("#2BC8D4"),
            deep: ColorPair("#0E6A73"),
            onAccent: ColorPair("#04181B")
        )

        palette.chrome = ChromeColors(
            // Near-black with a cool bias. Pure black reads as an absence; a
            // blue-black reads as a considered ground.
            surface: ColorPair("#12161C"),
            plane: ColorPair("#080A0D"),
            textPrimary: ColorPair("#EAF0F6"),
            textSecondary: ColorPair("#9FB0C2"),
            textMuted: ColorPair("#647689"),
            gridline: ColorPair("#1E242C"),
            axis: ColorPair("#2A323C"),
            border: ColorPair("#1E242C"),
            deltaPositive: ColorPair("#35C77A"),
            deltaNegative: ColorPair("#E06B6A")
        )

        // Single-series charts take the brand, so a lone chart reads as part of
        // the app rather than as a guest from the data palette.
        palette.sequential = [
            ColorPair("#06343A"), ColorPair("#0A4A52"), ColorPair("#0E6A73"),
            ColorPair("#128A96"), ColorPair("#16A7B5"), ColorPair("#2BC8D4"),
            ColorPair("#5BDAE3"), ColorPair("#8CE8EE"), ColorPair("#B6F2F5"),
            ColorPair("#DAF9FB")
        ]
        palette.sequentialOrdinalFloorIndex = 1

        // The commitment: no per-tracker hues. Trackers separate by intensity
        // within the brand ramp, so green, amber and red on screen can only ever
        // mean status.
        palette.identityMode = .brandMonochrome

        return palette
    }()
}

// MARK: - Nocturne theme

public extension TrackerTheme {

    /// Dark, premium, committed.
    ///
    /// Deliberately a **single-appearance design**. It does not adapt to light
    /// mode, because half the character is the near-black ground and a
    /// "light Nocturne" would be a different product wearing the same name. Host
    /// apps that need both should use ``standard``, which is designed for both.
    static let nocturne = TrackerTheme(
        palette: .nocturne,
        typography: Typography(
            displayDesign: .rounded,
            // Display sits tight and heavy; body stays neutral. The contrast
            // between the two is what carries the hierarchy, not size alone.
            headingWeight: .semibold,
            displayWeight: .heavy,
            labelTracking: 1.4,
            displayTracking: -1.4
        ),
        spacing: Spacing(unit: 8, density: .comfortable),
        radii: Radii(card: 22, control: 16, well: 12, tile: 24, usesConcentric: true),
        surfaces: Surfaces(
            control: .glass,
            // Filled rather than elevated: on a near-black ground a drop shadow
            // is invisible, and a hairline on every card turns the screen into a
            // wireframe. Separation comes from the value step between plane and
            // surface instead.
            card: .filled,
            shadowOpacity: 0,
            shadowRadius: 0,
            heroWash: 0.30,
            tintsGlass: true
        ),
        metrics: {
            var metrics = TrackerTheme.Metrics()
            metrics.lineWidth = 2.5
            metrics.markCornerRadius = 3
            metrics.ringWidth = 15
            metrics.ringSpacing = 7
            metrics.gridLineWidth = 0.5
            return metrics
        }(),
        motion: {
            var motion = TrackerTheme.Motion()
            motion.bounce = 0.22
            motion.fillDuration = 1.05
            motion.stagger = 0.05
            return motion
        }(),
        preferredColorScheme: .dark
    )
}

// MARK: - Forced appearance

public extension View {
    /// Locks this subtree to the appearance a single-appearance theme requires.
    ///
    /// Only themes that deliberately commit to one look use this. A theme
    /// designed for both appearances must never call it — overriding the
    /// viewer's choice when you didn't need to is hostile.
    @ViewBuilder
    func trackerForcedAppearance(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
