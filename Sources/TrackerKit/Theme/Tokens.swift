import SwiftUI

// MARK: - Spacing

/// The spacing scale. Every gap and inset in the library comes from here.
///
/// Built on an 8pt grid because that is what the platform's own layouts land on,
/// with a density multiplier so the same design can breathe on an iPad and
/// tighten up on a phone without re-authoring a single view.
public struct Spacing: Sendable, Hashable {

    public enum Density: String, Sendable, CaseIterable, Hashable {
        case compact
        case comfortable
        case spacious

        var multiplier: CGFloat {
            switch self {
            case .compact: 0.82
            case .comfortable: 1.0
            case .spacious: 1.22
            }
        }

        public var displayName: String { rawValue.capitalized }
    }

    /// The grid unit everything derives from.
    public var unit: CGFloat
    public var density: Density

    public init(unit: CGFloat = 8, density: Density = .comfortable) {
        self.unit = unit
        self.density = density
    }

    /// `n` grid steps, rounded to whole points so nothing lands on a half pixel.
    public func step(_ n: Double) -> CGFloat {
        (unit * CGFloat(n) * density.multiplier).rounded()
    }

    // Scale tokens
    public var xs: CGFloat { step(0.5) }
    public var sm: CGFloat { step(1) }
    public var md: CGFloat { step(1.5) }
    public var lg: CGFloat { step(2) }
    public var xl: CGFloat { step(3) }
    public var xxl: CGFloat { step(4) }

    // Semantic tokens — say what the space is *for*, not how big it is.
    public var cardPadding: CGFloat { step(2) }
    public var cardGap: CGFloat { step(1.5) }
    public var screenMargin: CGFloat { step(2) }
    public var sectionGap: CGFloat { step(2.5) }
    public var rowGap: CGFloat { step(1.25) }
    public var inlineGap: CGFloat { step(0.75) }

    /// The hairline gap punched between adjacent chart marks. Deliberately not
    /// scaled by density — 2pt is a rendering constant, not a layout choice.
    public var markGap: CGFloat { 2 }
}

// MARK: - Radii

/// Corner radii, and whether they follow the hardware.
///
/// iOS 26 can make a container's corners *concentric* with the screen's, so a
/// card near the edge curves in sympathy with the device instead of fighting it.
/// That is the "Harmony" principle in Apple's own framing, and it is one of the
/// cheapest ways to make an interface feel native rather than ported.
public struct Radii: Sendable, Hashable {
    public var card: CGFloat
    public var control: CGFloat
    public var well: CGFloat
    public var tile: CGFloat
    /// When true, cards use `ConcentricRectangle` and inherit the container's
    /// curvature, falling back to `card` as a minimum.
    public var usesConcentric: Bool
    /// Whether floating actions are fully rounded. A capsule is the iOS 26 idiom
    /// for a floating control; a squared theme should override it or the identity
    /// falls apart at exactly the moment the user is looking at the button.
    public var usesCapsuleActions: Bool

    public init(
        card: CGFloat = 20,
        control: CGFloat = 14,
        well: CGFloat = 10,
        tile: CGFloat = 22,
        usesConcentric: Bool = true,
        usesCapsuleActions: Bool = true
    ) {
        self.card = card
        self.control = control
        self.well = well
        self.tile = tile
        self.usesConcentric = usesConcentric
        self.usesCapsuleActions = usesCapsuleActions
    }

    /// The shape a card should be drawn in.
    public var cardShape: AnyShape {
        usesConcentric
            ? AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(card)), isUniform: true))
            : AnyShape(RoundedRectangle(cornerRadius: card))
    }

    public var controlShape: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: control))
    }

    public var wellShape: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: well))
    }

    /// Shape for a floating action — the primary button in a control cluster.
    public var actionShape: AnyShape {
        usesCapsuleActions ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: control))
    }

    /// Shape for a circular secondary action, squared off when the theme is.
    public var actionAccessoryShape: AnyShape {
        usesCapsuleActions ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: control))
    }

    public static let standard = Radii()
    /// Squared-off, for a more editorial or technical feel.
    public static let square = Radii(
        card: 4, control: 4, well: 3, tile: 4,
        usesConcentric: false, usesCapsuleActions: false
    )
    /// Very round, for a softer, friendlier read.
    public static let soft = Radii(card: 28, control: 20, well: 14, tile: 30)
}

// MARK: - Surfaces

/// How the two layers of the interface are drawn.
///
/// The split matters more than any single value here. Apple's Liquid Glass is a
/// **navigation-layer** material: it samples what is behind it, so it works when
/// it floats over content and degrades into visual noise when it *is* the
/// content. This type keeps that distinction explicit — `control` governs
/// toolbars, tab bars and floating actions; `card` governs everything the user
/// is actually reading.
public struct Surfaces: Sendable, Hashable {

    /// Treatment for the navigation and control layer.
    public enum ControlTreatment: String, Sendable, CaseIterable, Hashable {
        /// Liquid Glass, tinted by the accent.
        case glass
        /// Liquid Glass with the clear variant — for controls over imagery.
        case glassClear
        /// Opaque surface with a hairline. No glass anywhere.
        case solid

        public var displayName: String {
            switch self {
            case .glass: "Glass"
            case .glassClear: "Clear glass"
            case .solid: "Solid"
            }
        }
    }

    /// Treatment for content cards.
    public enum CardTreatment: String, Sendable, CaseIterable, Hashable {
        /// Surface colour, hairline border, soft shadow.
        case elevated
        /// Surface colour and a hairline, no shadow. Flatter, more editorial.
        case outlined
        /// Fills against the page with no border at all — relies on the value
        /// difference between plane and surface to separate.
        case filled

        public var displayName: String { rawValue.capitalized }
    }

    public var control: ControlTreatment
    public var card: CardTreatment
    /// Shadow strength for `.elevated`. Zero reads flat.
    public var shadowOpacity: Double
    public var shadowRadius: CGFloat
    /// Strength of the accent wash behind hero sections, 0...1.
    public var heroWash: Double
    /// Whether glass controls pick up the accent tint.
    public var tintsGlass: Bool

    public init(
        control: ControlTreatment = .glass,
        card: CardTreatment = .elevated,
        shadowOpacity: Double = 0.06,
        shadowRadius: CGFloat = 14,
        heroWash: Double = 0.16,
        tintsGlass: Bool = true
    ) {
        self.control = control
        self.card = card
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.heroWash = heroWash
        self.tintsGlass = tintsGlass
    }

    public static let standard = Surfaces()
    public static let flat = Surfaces(
        control: .solid, card: .outlined, shadowOpacity: 0, shadowRadius: 0, heroWash: 0.10, tintsGlass: false
    )
    public static let glassy = Surfaces(
        control: .glass, card: .filled, shadowOpacity: 0.10, shadowRadius: 20, heroWash: 0.24
    )
}
