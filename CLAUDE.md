# TrackerKit — project notes

Reusable iOS tracking library. Built 2026-09-17. See `README.md` for the full
picture; this file is the working context for changing it.

## Layout

```
tracker_library_ios/
├── Package.swift              — SPM, tools 6.2, iOS 26+, Swift 5 language mode
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
│   └── UI/                    — assembled screens
├── Tests/TrackerKitTests/     — 75 tests
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

## Commands

```bash
# Library
xcodebuild -scheme TrackerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme TrackerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

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

## Open items

- Widget extension target isn't built — the views and snapshot plumbing exist,
  but the extension has to be created in a host app project.
- Repo: `git@github.com:mightylodek/TrackerKit.git` (public), branch `main`.
- The demo app runs in-memory; flip `inMemory: false` in `TrackerKitDemoApp` to
  exercise real persistence and migration.
