# TrackerKit — project notes

Reusable iOS tracking library. Built 2026-09-17. See `README.md` for the full
picture; this file is the working context for changing it.

## Layout

```
tracker_library_ios/
├── Package.swift              — SPM, tools 6.2, iOS 26+ / watchOS 26+, Swift 5 mode
├── Sources/TrackerKit/
│   ├── Model/                 — value types, SwiftData records, enums, formatters
│   ├── Engine/                — pure calculation: periods, progress, stoplight, streaks, trends
│   ├── Store/                 — TrackerStore, ProfileSession, SampleData
│   ├── Security/              — SecretStorage, KeychainStore, PINManager
│   ├── Theme/                 — ChartPalette, Typography, Tokens, TrackerTheme
│   ├── Charts/                — every visual
│   ├── Motion/                — animated numbers, progress replay
│   ├── Hero/                  — hero sections, ProfileAvatar
│   ├── Widgets/               — WidgetSnapshot, shared store, S/M/L views
│   ├── Export/                — report model, 4 renderers, scheduler, composers
│   └── UI/                    — assembled screens (iOS-only, see rule 17)
├── Tests/TrackerKitTests/     — 110 tests
├── Demo/TrackerDashUITests/   — 17 UI tests (taps, not just draws)
└── Demo/TrackerKitDemo.xcodeproj
```

## Visual direction

**Nocturne is the shipped identity** — dark-first teal monochrome, chosen by the
owner on 2026-09-17. `.standard`, `.editorial` and `.vivid` are kept and
supported but are not the default. Nocturne's rule is one sentence: *the app is
one colour; colour means status.* Don't introduce a new hue into chrome without
checking it against the status palette first.

## Rules that hold the design together

Break these and things get subtly wrong rather than obviously broken.

1. **Goals are append-only.** Never mutate a `GoalVersion` in place except through
   `TrackerStore.setGoal`, which edits only when `effectiveFrom` lands on the same
   day. Rewriting a goal makes every historical chart lie.
2. **Engines stay pure.** No SwiftUI, no SwiftData in `Engine/`. They take value
   types and return value types. That's what makes them testable against fixed
   dates and reusable from a widget extension.
3. **Views don't touch `ModelContext`.** Everything goes through `TrackerStore`.
4. **Caches are `@ObservationIgnored`.** A cache filled from inside a view body
   that isn't ignored registers as a mutation and loops the renderer.
5. **Status is never color alone.** Every stoplight ships a glyph and a word.
6. **Don't stack series with different units.** See the note on
   `TrackerStackedBarChart`.
7. **Assign categorical colors in fixed order, never cycled.** Color follows the
   entity, not its position in a filtered list.
8. **Views never name a raw value.** No literal font sizes, paddings, radii or
   hexes in a view — read `theme.typography`, `theme.spacing`, `theme.radii`,
   `theme.palette`. This is the whole reason a rebrand is one assignment.
9. **Brand colour and data colour are separate systems.** `theme.accent` comes
   from `palette.brand`, never from `palette.series(0)`. The categorical palette
   is for multi-series charts only.
10. **Never put page ink on a tinted control.** Use
   `theme.inkOnControl(isProminent:)` — a prominent control is tinted with the
   accent, so its label sits on the accent, not on the page.
11. **State wins over identity on any mark that can carry both.** Progress bars
   take the status colour; the tracker's own colour is the fallback for unscored
   data only. Series and status palettes are close in hue and must not both
   colour one mark.
12. **A list of things is drawn as a list**, not as N floating cards. One
   container, hairline separators. Rows needing attention get a faint
   status-tinted ground — information, not decoration.
13. **Identity colours the achievement; critical colours the breach.** Any
   progress visual for an `.atMost` goal must draw its overshoot in the critical
   colour — see `ProgressSnapshot.breachesLimit`. A full ring or bar must never
   read as success when the goal was a ceiling.
14. **Prefer the system component.** `ContentUnavailableView` for empty states,
   `Label` for icon-plus-text, hierarchical styles over manual opacity. The
   library's job is tracking, not re-implementing UIKit's empty state.
15. **44×44 minimum on every interactive element** — `.trackerTouchTarget()`.
16. **Glass belongs to the control layer only.** Use `.trackerControlSurface()`
   for floating actions and toolbars, `.trackerCardSurface()` for content. Glass
   on a content card defeats its sampling model and looks like mud.

17. **`UI/` is iOS-only; everything else compiles for watchOS too.** Every file in
   `Sources/TrackerKit/UI/` sits behind `#if os(iOS)`, as does `Chart3DView`.
   `Model/`, `Engine/`, `Store/`, `Theme/`, `Security/`, `Charts/` and `Widgets/`
   are shared and must build for both — the watchOS test run enforces it, so run
   it before adding a UIKit call to the shared layer. A watch app gets its own
   views on the same core, never these ones shrunk.

## Commands

```bash
# Library — iOS
xcodebuild -scheme TrackerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme TrackerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Library — watchOS (guards the shared/iOS-only boundary; 109 of 110 tests run here)
xcodebuild -scheme TrackerKit -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' build
xcodebuild test -scheme TrackerKit -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' 

# Demo app
cd Demo && xcodebuild -project TrackerKitDemo.xcodeproj -scheme TrackerKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run it, skipping the picker
env SIMCTL_CHILD_TKDEMO_PROFILE=Alex SIMCTL_CHILD_TKDEMO_TAB=gallery \
  xcrun simctl launch --terminate-running-process "iPhone 17 Pro" com.trackerkit.demo
```

## Adding a visual

1. Put it in `Sources/TrackerKit/Charts/` with a `#Preview`.
2. Read colors from `@Environment(\.trackerTheme)` — never hardcode a hex.
3. Add it to `ChartGalleryView` in the right section.
4. Add it to `RenderSmokeTests`, **including the degenerate-input test**. Empty
   arrays and all-zero series are where chart views trap.

## Verifying visuals

`glassEffect` is composited at display time, so offscreen renders drop it and a
`GlassEffectContainer` can blank its entire subtree. Consequences:

- The catalog generator (`TRACKERKIT_CATALOG=1`) is reliable for everything
  *except* screens with glass.
- To check a glass screen, run it:
  `env SIMCTL_CHILD_TKDEMO_DETAIL=Focus SIMCTL_CHILD_TKDEMO_THEME=vivid xcrun simctl launch ...`
- `23-glass-probe.png` in the catalog is the canary: if its GLASS capsule is
  missing while SOLID renders, you are looking at the harness, not a bug.

## Planned work with notes already written

- `docs/INTERACTIVE-WIDGETS.md` — what changes when a widget can write. Includes
  red-team prompts. **Goes through a blue/red team review before any code.**
- `docs/WATCH.md` — standalone watchOS app (the kids have watches, not phones).
  **Step 1 is done**: the package builds and tests on watchOS. Step 2 is a watch
  target with one screen, but two product questions come first — whether a
  personal watch needs profiles at all, and how a tracker gets created with no
  phone in the house (templates are the likely answer).

## Dashboard layout

`DashboardCard` is the unit. Layouts live per profile as JSON on `ProfileRecord`
(read and written whole, ordering is the point). Adding a visual means: a `Kind`
case, a branch in `DashboardCardView`, and an `addable:` on its gallery entry.
Tracker-scoped cards must tolerate their tracker being deleted — `canRender`
decides, and the editor explains.

## Open items

- Widget extension is built and working (`Demo/TrackerDashWidgets`), display-only.
- Repo: `git@github.com:mightylodek/TrackerKit.git` (public), branch `main`.
- The demo app runs **on-disk**. Automated runs opt into a clean slate with
  `TKDEMO_INMEMORY=1`, which the UI test classes set. Persistence across relaunch
  is covered by `PersistenceUITests`; durability over days/reboots is a device
  question — see `docs/DEVICE-TEST-PLAN.md`.
- `swift test` does **not** work: it builds for macOS, where `MessageUI` is
  missing. Always use `xcodebuild` with a simulator destination.
- Testing guide: `docs/TESTING.md`. Device plan: `docs/DEVICE-TEST-PLAN.md`.
