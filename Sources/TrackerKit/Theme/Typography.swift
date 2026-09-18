import SwiftUI

/// The type system, expressed as roles rather than sizes.
///
/// Views ask for `theme.typography.heading`, never `.system(size: 17)`. That is
/// the whole trick behind rebranding cheaply: swapping a brand's display face is
/// one assignment here, and every screen picks it up.
///
/// Custom faces are registered through `Font.custom(_:size:relativeTo:)`, so they
/// keep scaling with Dynamic Type. A brand font that ignores accessibility text
/// sizes is a bug, not a style.
public struct Typography: Sendable, Hashable {

    /// Font family for display and heading roles. `nil` uses the system face.
    public var displayFamily: String?
    /// Font family for body and label roles. `nil` uses the system face.
    public var bodyFamily: String?
    /// Family for figures and tabular data. `nil` uses the system face with
    /// monospaced digits, which is usually the right answer.
    public var numericFamily: String?

    /// Design applied when no custom family is set.
    public var systemDesign: Font.Design
    /// Design for display roles specifically — a rounded display over a default
    /// body is a common and effective pairing.
    public var displayDesign: Font.Design

    /// Multiplies every role's size. For tuning density, not for accessibility —
    /// Dynamic Type already handles that.
    public var scale: Double

    /// Extra weight applied to headings. Some brand faces need a nudge.
    public var headingWeight: Font.Weight
    public var displayWeight: Font.Weight

    /// Letter spacing for the uppercase label role, in points.
    public var labelTracking: CGFloat
    /// Letter spacing for display-role text, in points. Negative tightens.
    ///
    /// Large type set at default tracking looks loose; tightening it is most of
    /// what separates a considered headline from a default one.
    public var displayTracking: CGFloat

    public init(
        displayFamily: String? = nil,
        bodyFamily: String? = nil,
        numericFamily: String? = nil,
        systemDesign: Font.Design = .default,
        displayDesign: Font.Design = .rounded,
        scale: Double = 1.0,
        headingWeight: Font.Weight = .semibold,
        displayWeight: Font.Weight = .bold,
        labelTracking: CGFloat = 0.6,
        displayTracking: CGFloat = 0
    ) {
        self.displayFamily = displayFamily
        self.bodyFamily = bodyFamily
        self.numericFamily = numericFamily
        self.systemDesign = systemDesign
        self.displayDesign = displayDesign
        self.scale = scale
        self.headingWeight = headingWeight
        self.displayWeight = displayWeight
        self.labelTracking = labelTracking
        self.displayTracking = displayTracking
    }

    // MARK: Roles

    /// The hero number or screen title. Used sparingly — one per screen.
    public var display: Font { display(.largeTitle) }
    /// A large figure inside a card.
    public var figure: Font { display(.title) }
    /// Section and card titles.
    public var title: Font { styled(.title3, family: displayFamily, weight: headingWeight, design: displayDesign) }
    /// Row titles, emphasised labels.
    public var heading: Font { styled(.headline, family: displayFamily, weight: headingWeight, design: displayDesign) }
    /// Running text.
    public var body: Font { styled(.body, family: bodyFamily, weight: .regular, design: systemDesign) }
    /// Secondary running text.
    public var callout: Font { styled(.callout, family: bodyFamily, weight: .regular, design: systemDesign) }
    /// Supporting text under a heading.
    public var subheadline: Font { styled(.subheadline, family: bodyFamily, weight: .regular, design: systemDesign) }

    /// Small supporting text.
    ///
    /// Deliberately mapped to `.footnote`, not `.caption`. Caption is already on
    /// the small side and caption2 is smaller still; defaulting to them is how
    /// interfaces end up unreadable at arm's length or at accessibility sizes.
    public var label: Font { styled(.footnote, family: bodyFamily, weight: .regular, design: systemDesign) }
    /// Emphasised small text — chips, badges, status words.
    public var labelEmphasis: Font { styled(.footnote, family: displayFamily, weight: .semibold, design: displayDesign) }
    /// The smallest text the system should ever render here. Axis ticks, legends.
    /// If you reach for this anywhere a person must *read* rather than *scan*,
    /// use ``label`` instead.
    public var micro: Font { styled(.caption, family: bodyFamily, weight: .regular, design: systemDesign) }
    /// Uppercase eyebrow labels. Pair with ``labelTracking``.
    public var eyebrow: Font { styled(.caption, family: displayFamily, weight: .semibold, design: displayDesign) }

    // MARK: Figures

    /// A number that must line up in a column.
    public func numeric(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        styled(style, family: numericFamily, weight: weight, design: systemDesign)
            .monospacedDigit()
    }

    /// A large standalone figure, at an explicit point size.
    public func display(_ style: Font.TextStyle) -> Font {
        styled(style, family: displayFamily, weight: displayWeight, design: displayDesign)
    }

    /// An arbitrary size in the display role — for hero numbers that need to fill
    /// a specific space. Still scales with Dynamic Type.
    public func displaySize(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        let scaled = size * scale
        if let displayFamily {
            return .custom(displayFamily, size: scaled, relativeTo: style).weight(displayWeight)
        }
        return .system(size: scaled, weight: displayWeight, design: displayDesign)
    }

    // MARK: Construction

    private func styled(
        _ style: Font.TextStyle,
        family: String?,
        weight: Font.Weight,
        design: Font.Design
    ) -> Font {
        if let family {
            return .custom(family, size: Self.baseSize(style) * scale, relativeTo: style)
                .weight(weight)
        }
        if scale == 1.0 {
            // Prefer the semantic style so Dynamic Type behaves exactly as the
            // system intends when nothing has been customized.
            return .system(style, design: design).weight(weight)
        }
        return .system(size: Self.baseSize(style) * scale, weight: weight, design: design)
    }

    /// Default point sizes for each text style at the standard content size.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    // MARK: Presets

    /// System faces throughout, rounded display. The default.
    public static let standard = Typography()

    /// A serif display over a system body — reads considered and editorial.
    /// New York ships with the OS, so this needs no bundled font.
    public static let editorial = Typography(
        displayFamily: nil,
        bodyFamily: nil,
        systemDesign: .serif,
        displayDesign: .serif,
        headingWeight: .semibold,
        displayWeight: .bold,
        labelTracking: 1.0
    )

    /// Tighter and more mechanical — a monospaced numeric role throughout.
    public static let technical = Typography(
        systemDesign: .default,
        displayDesign: .default,
        scale: 0.97,
        headingWeight: .semibold,
        displayWeight: .heavy,
        labelTracking: 1.1
    )
}
