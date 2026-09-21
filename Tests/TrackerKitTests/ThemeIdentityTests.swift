// iOS-only: resolving a dynamic colour against a named appearance needs
// `UITraitCollection`, which watchOS does not have — and does not need, having
// no light appearance to resolve against.
#if os(iOS)

import Testing
import SwiftUI
import UIKit
@testable import TrackerKit

/// How identity colour resolves, and why profiles and trackers differ.
///
/// Every assertion resolves to concrete RGB first. `Color(light:dark:)` wraps a
/// UIColor with a dynamic provider, and two of those are never `==` even when
/// they paint identically — so comparing `Color` values directly produces tests
/// that pass whatever the code does.
@Suite("Theme identity")
struct ThemeIdentityTests {

    private var nocturne: TrackerTheme { .nocturne }

    /// Concrete channel values in a named appearance.
    private func rgb(_ color: Color, dark: Bool = true) -> [CGFloat] {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 1000).rounded() / 1000 }
    }

    @Test("Nocturne really is brand-monochrome")
    func nocturneIsMonochrome() {
        #expect(nocturne.palette.identityMode == .brandMonochrome)
    }

    /// The reported bug: pick an orange swatch, get a teal avatar.
    @Test("A profile keeps the colour that was picked, even in monochrome")
    func profileKeepsItsColour() {
        let picked = nocturne.palette.categorical[1]
        let profile = Profile(name: "Sam", colorHex: picked.light)

        #expect(rgb(nocturne.identityColor(for: profile)) == rgb(picked.color))
    }

    /// Two profiles that picked differently must not collapse to one colour —
    /// telling them apart is the entire point on a shared device.
    @Test("Different profile colours stay different")
    func profileColoursStayDistinct() {
        let a = Profile(name: "A", colorHex: nocturne.palette.categorical[0].light)
        let b = Profile(name: "B", colorHex: nocturne.palette.categorical[1].light)

        #expect(rgb(nocturne.identityColor(for: a)) != rgb(nocturne.identityColor(for: b)))
    }

    /// Two profiles that never picked anything still must not be identical.
    @Test("A profile colour survives both appearances")
    func resolvesInBothAppearances() {
        let picked = nocturne.palette.categorical[3]
        let profile = Profile(name: "Sam", colorHex: picked.light)

        #expect(rgb(nocturne.identityColor(for: profile), dark: true) == rgb(picked.color, dark: true))
        #expect(rgb(nocturne.identityColor(for: profile), dark: false) == rgb(picked.color, dark: false))
    }

    /// Trackers are the other way round on purpose: they're data marks, and
    /// monochrome exists so status is the only meaningful colour on a chart.
    @Test("A tracker's hue is still folded into the brand ramp")
    func trackerHueIsFolded() {
        let orange = nocturne.palette.categorical[1].light
        #expect(rgb(nocturne.identityColor(hex: orange, seed: 0)) != rgb(Color(hex: orange)))
    }

    @Test("A picked colour resolves to the palette pair, not the raw hex")
    func pickedColourResolvesToPair() {
        let pair = nocturne.palette.categorical[2]
        #expect(nocturne.palette.pair(matchingLightHex: pair.light) == pair)
        #expect(nocturne.palette.pair(matchingLightHex: "#123456") == nil)
    }

    /// A theme that keeps per-tracker hues must be unaffected by all of this.
    @Test("Categorical themes are unchanged")
    func categoricalUnchanged() {
        let theme = TrackerTheme.standard
        let hex = theme.palette.categorical[3].light
        #expect(rgb(theme.identityColor(hex: hex, seed: 0)) == rgb(Color(hex: hex)))
    }
}

#endif
