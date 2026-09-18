import SwiftUI

/// Everything visual that TrackerKit reads at render time.
///
/// The whole point of this type is that **rebranding is an assignment, not a
/// refactor**. Views never name a colour, a font size, a corner radius or a gap
/// directly — they ask the theme. Swapping a brand's identity means constructing
/// one of these, not touching fifty view files.
///
/// ```swift
/// TrackerKitRootView()
///     .trackerTheme(.standard.with {
///         $0.palette = myBrandPalette
///         $0.typography.displayFamily = "Söhne-Buch"
///         $0.radii = .square
///     })
/// ```
public struct TrackerTheme: Sendable, Hashable {

    /// Colour, by the job it does. See ``ChartPalette``.
    public var palette: ChartPalette
    /// Type, by role. See ``Typography``.
    public var typography: Typography
    /// The 8pt grid and its density. See ``Spacing``.
    public var spacing: Spacing
    /// Corner radii and hardware concentricity. See ``Radii``.
    public var radii: Radii
    /// How the control layer and the content layer are drawn. See ``Surfaces``.
    public var surfaces: Surfaces
    /// Chart mark geometry — stroke widths, marker sizes, ring thickness.
    public var metrics: Metrics
    /// Animation timings.
    public var motion: Motion

    /// Forces an appearance for themes that deliberately commit to one look.
    /// `nil` — the default — means the theme adapts to the viewer's setting,
    /// which is what a well-behaved theme does.
    public var preferredColorScheme: ColorScheme?

    // MARK: Metrics

    /// Geometry for chart marks specifically.
    ///
    /// Distinct from ``Spacing`` on purpose: these are *rendering* constants that
    /// keep a chart legible, not layout choices. A 2pt line stays a 2pt line
    /// whether the app is running compact or spacious.
    public struct Metrics: Sendable, Hashable {
        /// Stroke width for line and area outlines.
        public var lineWidth: CGFloat = 2
        /// Corner radius on the *data end* of a bar. The baseline end stays square.
        public var markCornerRadius: CGFloat = 4
        /// Minimum touch-friendly point marker diameter.
        public var markerSize: CGFloat = 8
        /// Gap punched between adjacent fills so they read as separate marks.
        public var surfaceGap: CGFloat = 2
        public var gridLineWidth: CGFloat = 0.5
        /// Default height for an inline chart inside a card.
        public var chartHeight: CGFloat = 180
        /// Ring thickness on the activity-rings visual.
        public var ringWidth: CGFloat = 14
        public var ringSpacing: CGFloat = 6
        /// Minimum interactive target. Apple's floor is 44×44 and this library
        /// enforces rather than approximates it.
        public var minimumTouchTarget: CGFloat = 44

        public init() {}
    }

    // MARK: Motion

    /// Animation timing. One place so progress bars, rings and replays agree.
    public struct Motion: Sendable, Hashable {
        /// Whether progress visuals animate in on appear at all.
        public var animatesOnAppear: Bool = true
        /// Duration of a fill/ring sweep.
        public var fillDuration: Double = 0.9
        /// Duration of a number counting up.
        public var countUpDuration: Double = 0.8
        /// Delay between staggered siblings.
        public var stagger: Double = 0.06
        /// Seconds per step when replaying history over time.
        public var replayStepDuration: Double = 0.12
        /// How much bounce state changes carry. Springs read as physical; eased
        /// curves read as software. Zero gives a flat, mechanical feel.
        public var bounce: Double = 0.28

        public init() {}

        /// The long sweep used by fills and rings.
        public var fillAnimation: Animation {
            .spring(duration: fillDuration, bounce: bounce)
        }

        /// The short response used by taps, toggles and selections.
        public var snappyAnimation: Animation {
            .spring(duration: 0.34, bounce: bounce * 0.75)
        }

        /// The morphing curve for glass and matched-geometry transitions.
        public var morphAnimation: Animation {
            .spring(duration: 0.5, bounce: bounce * 1.2)
        }
    }

    // MARK: Init

    public init(
        palette: ChartPalette = .standard,
        typography: Typography = .standard,
        spacing: Spacing = Spacing(),
        radii: Radii = .standard,
        surfaces: Surfaces = .standard,
        metrics: Metrics = Metrics(),
        motion: Motion = Motion(),
        preferredColorScheme: ColorScheme? = nil
    ) {
        self.palette = palette
        self.typography = typography
        self.spacing = spacing
        self.radii = radii
        self.surfaces = surfaces
        self.metrics = metrics
        self.motion = motion
        self.preferredColorScheme = preferredColorScheme
    }

    /// Copy-and-tweak, so a host app can change one value without rebuilding the rest.
    public func with(_ mutate: (inout TrackerTheme) -> Void) -> TrackerTheme {
        var copy = self
        mutate(&copy)
        return copy
    }

    // MARK: Colour accessors

    public var surface: Color { palette.chrome.surface.color }
    public var plane: Color { palette.chrome.plane.color }
    public var textPrimary: Color { palette.chrome.textPrimary.color }
    public var textSecondary: Color { palette.chrome.textSecondary.color }
    public var textMuted: Color { palette.chrome.textMuted.color }
    public var gridline: Color { palette.chrome.gridline.color }
    public var axis: Color { palette.chrome.axis.color }
    public var border: Color { palette.chrome.border.color }
    /// The one colour that carries brand identity. Series colours are identity
    /// for *data*; this is identity for the *app*, and they are now different
    /// systems — see ``ChartPalette/brand``.
    public var accent: Color { palette.brand.accent.color }
    /// The deep form of the brand, for large washes and blooms.
    public var accentDeep: Color { palette.brand.deep.color }
    /// Ink that sits legibly on the accent.
    public var onAccent: Color { palette.brand.onAccent.color }

    // MARK: Identity

    /// Resolves a stored identity colour through the theme.
    ///
    /// Under ``ChartPalette/IdentityMode/categorical`` this is just the stored
    /// hue. Under `brandMonochrome` the hue is discarded and the tracker is
    /// placed on the brand ramp by `seed`, so trackers stay distinguishable by
    /// intensity while the screen stays one colour.
    public func identityColor(hex: String, seed: Int = 0) -> Color {
        switch palette.identityMode {
        case .categorical:
            return Color(hex: hex)
        case .brandMonochrome:
            let ramp = palette.sequential
            guard ramp.count > 1 else { return palette.brand.accent.color }
            // Use the upper half of the ramp only — the lower steps are near the
            // ground and would render a tracker as almost invisible.
            let lower = max(palette.sequentialOrdinalFloorIndex, ramp.count / 2 - 1)
            let span = max(1, ramp.count - 1 - lower)
            let step = lower + (abs(seed) % (span + 1))
            return ramp[min(step, ramp.count - 1)].color
        }
    }

    /// Identity colour for a tracker, seeded by its position so the assignment is
    /// stable and ordered rather than random.
    public func identityColor(for tracker: Tracker) -> Color {
        identityColor(hex: tracker.colorHex, seed: tracker.sortIndex)
    }

    /// Identity colour for a profile.
    public func identityColor(for profile: Profile) -> Color {
        identityColor(hex: profile.colorHex, seed: profile.sortIndex)
    }

    /// Ink for a label sitting on a control surface.
    ///
    /// A prominent control is tinted with the accent, so its label has to sit on
    /// the accent rather than on the page. Using the page's primary ink there
    /// gives you near-white on a bright accent, which is how a "designed" button
    /// ends up illegible.
    public func inkOnControl(isProminent: Bool) -> Color {
        guard isProminent, surfaces.tintsGlass, surfaces.control != .solid else {
            return textPrimary
        }
        return onAccent
    }

    public func statusColor(_ status: StoplightStatus) -> Color {
        palette.status.color(for: status)
    }

    /// Ink for a delta figure, given whether the movement is favorable.
    public func deltaColor(isFavorable: Bool) -> Color {
        isFavorable ? palette.chrome.deltaPositive.color : palette.chrome.deltaNegative.color
    }

    // MARK: - Presets

    /// The validated default: cool neutrals, the colourblind-checked palette,
    /// glass on the control layer, rounded display type.
    public static let standard = TrackerTheme()

    /// Calm and considered. Serif type, squared corners, flat outlined cards, no
    /// glass, generous spacing. Reads like a well-set document rather than an app.
    public static let editorial = TrackerTheme(
        palette: .standard,
        typography: .editorial,
        spacing: Spacing(unit: 8, density: .spacious),
        radii: .square,
        surfaces: .flat,
        metrics: {
            var metrics = Metrics()
            metrics.markCornerRadius = 0
            metrics.lineWidth = 1.5
            return metrics
        }(),
        motion: {
            var motion = Motion()
            motion.bounce = 0.05
            motion.fillDuration = 0.7
            return motion
        }()
    )

    /// Dense and energetic. Tight spacing, soft corners, glass-forward, springy.
    /// Built for a kid tapping through a shared iPad at speed.
    public static let vivid = TrackerTheme(
        palette: .standard,
        typography: Typography(displayDesign: .rounded, displayWeight: .heavy),
        spacing: Spacing(unit: 8, density: .compact),
        radii: .soft,
        surfaces: .glassy,
        metrics: {
            var metrics = Metrics()
            metrics.markCornerRadius = 6
            metrics.lineWidth = 2.5
            metrics.ringWidth = 16
            return metrics
        }(),
        motion: {
            var motion = Motion()
            motion.bounce = 0.42
            motion.stagger = 0.045
            return motion
        }()
    )

    /// Every preset, for the theme switcher in the demo.
    /// Every preset, shipped identity first.
    public static let presets: [(name: String, theme: TrackerTheme)] = [
        ("Nocturne", .nocturne),
        ("Standard", .standard),
        ("Editorial", .editorial),
        ("Vivid", .vivid)
    ]
}

// MARK: - Backwards-compatible shims

public extension TrackerTheme.Metrics {
    /// Card corner radius. Kept so older call sites compile; new code should read
    /// `theme.radii.card` or use ``View/trackerCardSurface()``.
    @available(*, deprecated, message: "Use theme.radii.card")
    var cornerRadius: CGFloat { 20 }

    /// Card padding. Kept for older call sites; prefer `theme.spacing.cardPadding`.
    @available(*, deprecated, message: "Use theme.spacing.cardPadding")
    var cardPadding: CGFloat { 16 }
}

// MARK: - Environment

private struct TrackerThemeKey: EnvironmentKey {
    static let defaultValue: TrackerTheme = .standard
}

public extension EnvironmentValues {
    var trackerTheme: TrackerTheme {
        get { self[TrackerThemeKey.self] }
        set { self[TrackerThemeKey.self] = newValue }
    }
}

public extension View {
    /// Applies a theme to this view and everything below it.
    func trackerTheme(_ theme: TrackerTheme) -> some View {
        environment(\.trackerTheme, theme)
            .tint(theme.accent)
            .trackerForcedAppearance(theme.preferredColorScheme)
    }
}

// MARK: - Surface modifiers

/// Draws a content card in the theme's card treatment.
public struct TrackerCardSurface: ViewModifier {
    @Environment(\.trackerTheme) private var theme

    public func body(content: Content) -> some View {
        let shape = theme.radii.cardShape

        content
            .background {
                switch theme.surfaces.card {
                case .elevated, .outlined:
                    shape.fill(theme.surface)
                case .filled:
                    shape.fill(theme.surface)
                }
            }
            .overlay {
                if theme.surfaces.card != .filled {
                    shape.stroke(theme.border, lineWidth: 1)
                }
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(
                    theme.surfaces.card == .elevated ? theme.surfaces.shadowOpacity : 0
                ),
                radius: theme.surfaces.shadowRadius,
                y: theme.surfaces.shadowRadius * 0.25
            )
    }
}

/// Draws a **navigation or control** surface — a floating action bar, a toolbar
/// cluster, a segmented control.
///
/// This is the only place Liquid Glass belongs. Glass samples what sits behind
/// it, so it reads as a floating control over content and as mush when applied
/// to the content itself.
public struct TrackerControlSurface: ViewModifier {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape: AnyShape
    private let isProminent: Bool

    public init(shape: AnyShape? = nil, isProminent: Bool = false) {
        self.shape = shape ?? AnyShape(Capsule())
        self.isProminent = isProminent
    }

    public func body(content: Content) -> some View {
        // `case .glass, .glassClear where !reduceTransparency` would bind the
        // `where` to the *last* pattern only, silently ignoring Reduce
        // Transparency for the plain `.glass` case. Spell the condition out.
        if usesGlass {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(shape.fill(theme.surface))
                .overlay(shape.stroke(theme.border, lineWidth: 1))
        }
    }

    /// Glass is skipped entirely when the viewer has asked for less transparency —
    /// the system frosts it further on its own, but an opaque surface is the
    /// honest answer when someone has explicitly opted out.
    private var usesGlass: Bool {
        guard !reduceTransparency else { return false }
        switch theme.surfaces.control {
        case .glass, .glassClear: return true
        case .solid: return false
        }
    }

    private var glass: Glass {
        let base: Glass = theme.surfaces.control == .glassClear ? .clear : .regular
        let tinted = (theme.surfaces.tintsGlass && isProminent) ? base.tint(theme.accent) : base
        return tinted.interactive()
    }
}

public extension View {
    /// Content card: surface, border and shadow per the theme's card treatment.
    func trackerCardSurface() -> some View {
        modifier(TrackerCardSurface())
    }

    /// Control-layer surface: Liquid Glass where the theme asks for it.
    /// - Parameter isProminent: tints the glass with the accent, for the primary
    ///   action in a cluster.
    func trackerControlSurface(shape: AnyShape? = nil, isProminent: Bool = false) -> some View {
        modifier(TrackerControlSurface(shape: shape, isProminent: isProminent))
    }

    /// Enforces Apple's 44×44 minimum interactive target.
    func trackerTouchTarget(_ size: CGFloat = 44) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

// MARK: - TrackerCard

/// The standard surface a chart sits on: themed background, border, radius and
/// padding all read from tokens.
public struct TrackerCard<Content: View>: View {
    @Environment(\.trackerTheme) private var theme

    private let title: String?
    private let subtitle: String?
    private let content: Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cardGap) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: theme.spacing.xs * 0.5) {
                    if let title {
                        Text(title)
                            .font(theme.typography.title)
                            .foregroundStyle(theme.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            content
        }
        .padding(theme.spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trackerCardSurface()
    }
}
