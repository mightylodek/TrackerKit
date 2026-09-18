import SwiftUI

/// The color system every TrackerKit visual draws from.
///
/// Colors are assigned by the *job* they do, never picked per-chart:
///
/// - **Categorical** — identity. Eight fixed slots, assigned in order and never
///   cycled. A ninth series folds into "Other" or becomes a small multiple.
/// - **Sequential** — magnitude. One hue, light to dark.
/// - **Diverging** — polarity. Two poles with a neutral gray midpoint.
/// - **Status** — state. Reserved for stoplighting; never reused as a series color.
///
/// Light and dark steps are both *selected*, not derived — dark is the same eight
/// hues re-stepped for the dark surface.
///
/// ## Validation
/// The default categorical order passes every gate on the adjacent pairlist in
/// both modes: worst adjacent CVD ΔE 9.1 light / 8.4 dark (OKLab ×100, ≥8 target),
/// worst adjacent normal-vision ΔE 19.6 light / 19.3 dark (≥15 floor).
///
/// Two consequences are baked into the views and you should not undo them:
/// 1. Three light-mode slots sit under 3:1 against the light surface, so charts
///    ship **visible labels or a legend** — identity is never color-alone.
/// 2. For all-pairs forms (scatter, 3-D point clouds, small multiples) only the
///    **first three slots** validate. ``seriesCapForAllPairs`` enforces it.
public struct ChartPalette: Sendable, Hashable {

    // MARK: Categorical

    /// The eight identity slots, in fixed assignment order.
    /// Order is the colorblind-safety mechanism, not decoration — do not shuffle.
    public var categorical: [ColorPair]

    /// Maximum series before identity stops being readable in forms where every
    /// pair can appear side by side. Past this, fold to "Other" or facet.
    public let seriesCapForAllPairs = 3

    // MARK: Sequential

    /// One-hue magnitude ramp, lightest (near zero) to darkest.
    /// Used by the heatmap calendar and intensity fills.
    public var sequential: [ColorPair]

    /// The lightest step that still clears 2:1 on its surface — the floor for
    /// *ordinal* ramps (discrete ordered marks), where nothing may recede into
    /// the surface.
    public var sequentialOrdinalFloorIndex: Int

    // MARK: Diverging

    /// Cool pole — "below baseline".
    public var divergingLow: ColorPair
    /// Warm pole — "above baseline".
    public var divergingHigh: ColorPair
    /// Neutral midpoint. Deliberately gray: a hue here would read as a value.
    public var divergingMid: ColorPair

    // MARK: Status

    /// Stoplight colors. Fixed across themes and never themed per-profile —
    /// green must mean the same thing on every screen in the app.
    public var status: StatusColors

    // MARK: Identity expression

    /// How a tracker's stored colour is expressed on screen.
    public enum IdentityMode: String, Sendable, CaseIterable, Hashable {
        /// Each tracker keeps its own hue from the categorical palette.
        case categorical
        /// Hue is dropped; trackers are separated by *intensity* within the brand
        /// ramp instead. The screen becomes one colour, which makes the reserved
        /// status hues the only meaningful colour on it.
        case brandMonochrome

        public var displayName: String {
            switch self {
            case .categorical: "Per-tracker hue"
            case .brandMonochrome: "Brand monochrome"
            }
        }
    }

    /// Whether identity is carried by hue or by intensity.
    ///
    /// Tracker colours are *persisted data* — assigned once at creation and
    /// stable thereafter, which is right for identity. That stability is also why
    /// a theme alone could not make the app monochrome: the hues are in the
    /// database, not the theme. This switch is the seam. Storage keeps its hue;
    /// the theme decides whether to render it.
    public var identityMode: IdentityMode = .categorical

    // MARK: Brand

    /// The app's own identity colour, **separate from the data palette**.
    ///
    /// These were the same thing until they obviously shouldn't have been. The
    /// categorical palette is engineered for one job: eight hues maximally
    /// separated in OKLab so a colourblind reader can tell series apart. That is
    /// the opposite of a brand palette, which wants one dominant colour and a
    /// sharp accent. Using `series(0)` as the app accent meant the product's
    /// identity was whatever hue happened to sort first in a colourblindness
    /// optimisation — which is how an interface ends up looking like a system
    /// default rather than a product.
    public var brand: BrandColors

    // MARK: Chrome

    public var chrome: ChromeColors

    // MARK: - Nested types

    /// A color with a selected step for each appearance.
    public struct ColorPair: Sendable, Hashable {
        public var light: String
        public var dark: String

        public init(light: String, dark: String) {
            self.light = light
            self.dark = dark
        }

        /// Same step in both modes — used where a hue already sits in both bands.
        public init(_ both: String) {
            self.light = both
            self.dark = both
        }

        public var color: Color { Color(light: light, dark: dark) }
    }

    public struct StatusColors: Sendable, Hashable {
        public var good: ColorPair
        public var warning: ColorPair
        public var serious: ColorPair
        public var critical: ColorPair

        public init(good: ColorPair, warning: ColorPair, serious: ColorPair, critical: ColorPair) {
            self.good = good
            self.warning = warning
            self.serious = serious
            self.critical = critical
        }

        public func color(for status: StoplightStatus) -> Color {
            switch status {
            case .green: good.color
            case .yellow: warning.color
            case .red: critical.color
            case .neutral: Color(light: "#898781", dark: "#898781")
            }
        }
    }

    /// Identity colour for the application itself.
    public struct BrandColors: Sendable, Hashable {
        /// The sharp highlight: primary actions, selection, "now".
        public var accent: ColorPair
        /// The deep form of the brand, for large fills, blooms and washes where
        /// the accent would be overwhelming.
        public var deep: ColorPair
        /// Ink that sits legibly on top of ``accent``.
        public var onAccent: ColorPair

        public init(accent: ColorPair, deep: ColorPair, onAccent: ColorPair) {
            self.accent = accent
            self.deep = deep
            self.onAccent = onAccent
        }
    }

    public struct ChromeColors: Sendable, Hashable {
        /// The plane a chart is drawn on.
        public var surface: ColorPair
        /// The page behind the chart cards.
        public var plane: ColorPair
        public var textPrimary: ColorPair
        public var textSecondary: ColorPair
        /// Axis tick labels and other recessive text.
        public var textMuted: ColorPair
        public var gridline: ColorPair
        public var axis: ColorPair
        /// Hairline ring around cards and overlapping marks.
        public var border: ColorPair
        /// Text color for a favorable delta. Distinct from series green on purpose.
        public var deltaPositive: ColorPair
        public var deltaNegative: ColorPair

        public init(
            surface: ColorPair,
            plane: ColorPair,
            textPrimary: ColorPair,
            textSecondary: ColorPair,
            textMuted: ColorPair,
            gridline: ColorPair,
            axis: ColorPair,
            border: ColorPair,
            deltaPositive: ColorPair,
            deltaNegative: ColorPair
        ) {
            self.surface = surface
            self.plane = plane
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.textMuted = textMuted
            self.gridline = gridline
            self.axis = axis
            self.border = border
            self.deltaPositive = deltaPositive
            self.deltaNegative = deltaNegative
        }
    }

    // MARK: - Init

    public init(
        categorical: [ColorPair],
        sequential: [ColorPair],
        sequentialOrdinalFloorIndex: Int,
        divergingLow: ColorPair,
        divergingHigh: ColorPair,
        divergingMid: ColorPair,
        status: StatusColors,
        chrome: ChromeColors,
        brand: BrandColors? = nil
    ) {
        self.categorical = categorical
        self.sequential = sequential
        self.sequentialOrdinalFloorIndex = sequentialOrdinalFloorIndex
        self.divergingLow = divergingLow
        self.divergingHigh = divergingHigh
        self.divergingMid = divergingMid
        self.status = status
        self.chrome = chrome
        // Defaults to the first categorical slot so existing palettes are
        // unchanged until they opt into a real brand colour.
        self.brand = brand ?? BrandColors(
            accent: categorical.first ?? ColorPair("#0A84FF"),
            deep: categorical.first ?? ColorPair("#0A84FF"),
            onAccent: ColorPair("#ffffff")
        )
    }

    // MARK: - Lookup

    /// The identity color for series `index`.
    ///
    /// Beyond the eighth slot this wraps, but that is a **failure mode, not a
    /// feature** — nine identity colors cannot be told apart. Fold extra series
    /// into "Other" or split into small multiples before you get here.
    public func series(_ index: Int) -> Color {
        guard !categorical.isEmpty else { return .accentColor }
        return categorical[index % categorical.count].color
    }

    /// Series color as a raw hex string, for persisting a default on a new tracker.
    public func seriesHex(_ index: Int) -> String {
        guard !categorical.isEmpty else { return "#0A84FF" }
        return categorical[index % categorical.count].light
    }

    /// A step from the sequential ramp for a 0...1 magnitude.
    /// `ordinal: true` clamps to the contrast floor so no step recedes into the surface.
    public func sequentialStep(_ fraction: Double, ordinal: Bool = false) -> Color {
        guard !sequential.isEmpty else { return .accentColor }
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        let lowerBound = ordinal ? sequentialOrdinalFloorIndex : 0
        let span = sequential.count - 1 - lowerBound
        guard span > 0 else { return sequential[lowerBound].color }
        let index = lowerBound + Int((clamped * Double(span)).rounded())
        return sequential[min(index, sequential.count - 1)].color
    }

    /// A diverging step for a value in -1...1. Zero lands on the neutral midpoint.
    public func divergingStep(_ signed: Double) -> Color {
        let clamped = min(max(signed.isFinite ? signed : 0, -1), 1)
        if abs(clamped) < 0.05 { return divergingMid.color }
        let pole = clamped > 0 ? divergingHigh.color : divergingLow.color
        return pole.opacity(0.35 + 0.65 * abs(clamped))
    }

    // MARK: - Default

    /// The validated default palette. Swap these values for a brand palette and
    /// re-run the validator; the rest of TrackerKit reads roles, not hexes.
    public static let standard = ChartPalette(
        categorical: [
            ColorPair(light: "#2a78d6", dark: "#3987e5"),   // 1 blue
            ColorPair(light: "#eb6834", dark: "#d95926"),   // 2 orange
            ColorPair(light: "#1baf7a", dark: "#199e70"),   // 3 aqua
            ColorPair(light: "#eda100", dark: "#c98500"),   // 4 yellow
            ColorPair(light: "#e87ba4", dark: "#d55181"),   // 5 magenta
            ColorPair("#008300"),                            // 6 green
            ColorPair(light: "#4a3aa7", dark: "#9085e9"),   // 7 violet
            ColorPair(light: "#e34948", dark: "#e66767")    // 8 red
        ],
        sequential: [
            ColorPair(light: "#cde2fb", dark: "#0d366b"),
            ColorPair(light: "#b7d3f6", dark: "#104281"),
            ColorPair(light: "#9ec5f4", dark: "#184f95"),
            ColorPair(light: "#86b6ef", dark: "#1c5cab"),
            ColorPair(light: "#6da7ec", dark: "#256abf"),
            ColorPair(light: "#5598e7", dark: "#2a78d6"),
            ColorPair(light: "#3987e5", dark: "#3987e5"),
            ColorPair(light: "#2a78d6", dark: "#5598e7"),
            ColorPair(light: "#256abf", dark: "#6da7ec"),
            ColorPair(light: "#1c5cab", dark: "#86b6ef")
        ],
        sequentialOrdinalFloorIndex: 3,
        divergingLow: ColorPair(light: "#2a78d6", dark: "#3987e5"),
        divergingHigh: ColorPair(light: "#e34948", dark: "#e66767"),
        divergingMid: ColorPair(light: "#f0efec", dark: "#383835"),
        status: StatusColors(
            good: ColorPair("#0ca30c"),
            warning: ColorPair("#fab219"),
            serious: ColorPair("#ec835a"),
            critical: ColorPair("#d03b3b")
        ),
        // Dark chrome is biased slightly cool rather than warm-neutral. A neutral
        // grey dark mode reads as unconsidered; a hue bias toward the accent
        // reads as chosen. Re-validated after the change — the eight dark series
        // steps still clear 3:1 against this surface and hold their CVD margins.
        chrome: ChromeColors(
            surface: ColorPair(light: "#fcfcfb", dark: "#17191d"),
            plane: ColorPair(light: "#f7f8fa", dark: "#0d0e11"),
            textPrimary: ColorPair(light: "#0b0b0b", dark: "#f2f5f8"),
            textSecondary: ColorPair(light: "#52514e", dark: "#b7bfcb"),
            textMuted: ColorPair(light: "#898781", dark: "#8a919c"),
            gridline: ColorPair(light: "#e1e0d9", dark: "#262a31"),
            axis: ColorPair(light: "#c3c2b7", dark: "#343a43"),
            border: ColorPair(light: "#e1e0d9", dark: "#262a31"),
            deltaPositive: ColorPair(light: "#006300", dark: "#0ca30c"),
            deltaNegative: ColorPair(light: "#d03b3b", dark: "#e66767")
        )
    )
}
