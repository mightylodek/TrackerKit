# TrackerKit

A drop-in iOS library for habit and goal tracking: multiple profiles behind PIN
gates, daily login streaks, versioned goals, a large set of progress visuals, and
weekly progress exports.

Built to be brought into any future project with one dependency line and one view.

- **Swift 6.2 tools · iOS 26+ · SwiftUI · SwiftData · Liquid Glass**
- 56 source files, ~16,400 lines
- 76 tests, including a render pass over every visual
- Three shipped themes off one token system

---

## Quick start

```swift
import TrackerKit

@main
struct MyApp: App {
    init() { TrackerKit.configure() }

    var body: some Scene {
        WindowGroup {
            TrackerKitRootView(
                configuration: .init(appGroupIdentifier: "group.com.yourcompany.app")
            )
        }
    }
}
```

That gives you the profile picker, PIN gate, dashboard, visual gallery and export
settings. Everything underneath is public, so if you want your own navigation you
can ignore `TrackerKitRootView` and compose the pieces directly:

```swift
let store = TrackerStore(context: ModelContext(try TrackerKitSchema.container()))
let session = ProfileSession(store: store)

TrackerDashboardView(store: store, session: session)
    .trackerTheme(.standard)
```

### Installing

Add the package by path (or repo URL once it lives in one):

```swift
.package(path: "../tracker_library_ios")   // requires swift-tools-version 6.2+
```

then add `"TrackerKit"` to your target's dependencies. The demo project in
`Demo/` references it as a local package and is the working example.

---

## What's in it

### Data model

| Type | What it is |
|---|---|
| `Profile` | One person on the device. Everything else hangs off a profile. |
| `Tracker` | One habit, goal or metric. Five kinds: checkbox, count, duration, amount, rating. |
| `GoalVersion` | A goal as it stood during one stretch of time. **Append-only.** |
| `Entry` | One logged data point. |
| `LoginDay` | One day a profile opened the app — the raw material for streaks. |
| `ExportSchedule` | A standing weekly report instruction. |

Public API is value types (`Sendable`, `Codable`); SwiftData `@Model` records are
the storage layer behind `TrackerStore`. Views never touch a `ModelContext`.

### Engines

Pure, `Sendable`, no SwiftUI or SwiftData — unit-testable against fixed dates and
reusable from a widget extension.

- **`PeriodCalculator`** — turns dates into goal windows. Carries its own
  `Calendar`, which is what makes everything testable independent of device locale.
- **`ProgressEngine`** — rolls entries into scored periods.
- **`StoplightEngine`** — pace-aware traffic lights.
- **`StreakEngine`** — day streaks and goal streaks.
- **`TrendEngine`** — period-over-period deltas, moving averages, projections.

### Visuals

Everything is in the in-app **Gallery** tab, rendered against live data.

**Time series** — area (single and stacked), line (with moving average and
least-squares trend overlay), stacked bars, grouped bars, period bars colored by
stoplight, Canvas-drawn sparklines.

**Goals** — bullet charts (with target tick and pace projection), bullet lists,
stoplight rollup bar, status badges/dots at three sizes, progress replay.

**Rings & dials** — activity rings (overshoot draws a second lap rather than
capping), radial progress, semicircular gauge, mini progress bars.

Rings and bars follow two rules.

**State wins when there is one; identity fills in when there isn't.** The
categorical and status palettes sit close in hue by necessity — the reference
palette measures series-red against status-critical at ΔE 4.8 — so they must
never both colour the same mark. Progress bars carry state; identity lives in the
row's icon and sparkline, where nothing competes with it. Without this rule a
tracker assigned the red slot reads as failing when it is merely *red*, and one
assigned green reads as met when it is at risk.

**Identity colours the achievement, critical colours the breach.** Apple's Activity rings assume more is always better, which
is false for a ceiling — a screen-time ring at 115% looks like a win and is a
loss. Anything exceeding an `.atMost` goal draws its overshoot in the critical
colour, so a breach can never be mistaken for success.

**Calendars** — contribution heatmap, streak chain strip, streak cards and badges.

**3-D** — weekday × week and series × time, in two styles: `.columns` (hand-rolled
shaded columns over a ground grid, the default and the distinctive one) and
`.native` (Apple's `Chart3D` point field). Drag to rotate either.

**Widgets** — small, medium and large, driven by a `Codable` `WidgetSnapshot`.

**Heroes** — four styles (rings, headline, summary, compact).

**Motion** — count-up numbers, staggered entrances, pulse-on-change, and
`ProgressReplayView`, which animates history one period at a time with goal
changes called out as they happen.

---

## Three design decisions worth knowing about

### 1. Goals are versioned, never overwritten

Raising a target from 3 to 5 workouts a week writes a **new version effective
today** and leaves the old one intact. A chart of last month still renders against
the target that was actually in force back then.

```swift
store.setGoal(
    GoalVersion(target: 5, cadence: .weekly, unit: "x", note: "Raised it"),
    on: tracker.id
)
```

Which goal governs which period:

- **Past periods** use the goal that was in force when the period began — that's
  what makes old charts honest.
- **The current period** uses the goal in force right now, so a change takes
  effect immediately instead of next week.

Re-setting a goal on the same day it started **edits** that version instead of
splitting history, so fixing a typo doesn't become a chapter.

`GoalHistoryView` shows every version with the stretch it governed and the hit
rate under it. "I was hitting 4 a week easily, so I moved it to 6 and fell apart"
is a real pattern, and it's invisible in any app that overwrites the target.

### 2. Stoplights are pace-aware, with a grace window

Zero of five workouts on Monday is fine; the same zero on Saturday is not. A naive
`actual / target` paints both red and trains the user to ignore the color.

Two guards keep it from crying wolf:

- **`gracePace`** (default 0.25) — the opening quarter of a period isn't graded.
- **`minimumExpectation`** (default 1) — a shortfall doesn't count until at least
  one whole unit is expected. Strict pacing on a 5-per-week goal expects 0.7
  workouts on day one, and you cannot do most of a workout.

Presets: `.standard`, `.strict`, `.lenient`.

### 3. Exports remind, they don't send

**iOS does not let an app send email or SMS unattended.** There is no background
API for it, and anything claiming otherwise is routing through a server.

So `ExportScheduler` registers a **repeating local notification**. Tapping it opens
the app with a composer already filled in with the report — subject, body,
attachment. The user taps send. One tap a week, no infrastructure, and nothing
can fail silently in the background.

Four formats, all built from the same `ProgressReport` struct: **CSV** (with daily
detail rows), **Markdown** (doubles as an SMS body), **HTML** (self-contained,
inline SVG sparklines, no external assets), and **PDF** (paginated by item count
so a tracker's block is never sliced across a page break — it renders the same
SwiftUI charts the app shows).

`ProgressReport` is `Sendable` and format-agnostic, so if you ever do stand up a
server, that struct is the seam.

---

## Profiles and the PIN

Multiple people on one iPad, each with their own trackers, entries, streaks and
exports. A 4-digit PIN gates profile switching.

```swift
try session.setPIN("7391", for: profile)
session.select(profile)          // → .authenticating
session.submit(pin: "7391")      // → .success
```

**What the PIN is and isn't.** Four digits is a 10,000-combination secret. This is
a convenience gate — the thing that stops a sibling opening the wrong profile —
not encryption. The protections that actually matter at this key size are the ones
implemented:

- the PIN is never stored, only a salted hash, iterated 120,000 times;
- salt and hash live in the keychain, device-only, never synced to iCloud;
- failed attempts trigger an **escalating lockout** (1m → 5m → 15m → 1h), which is
  what makes brute-forcing 10,000 combinations impractical in person;
- verification is constant-time.

If you need real confidentiality behind that gate, layer file protection or a
passphrase-derived key on top. Don't ask four digits to do a job four digits
cannot do.

PIN storage sits behind the `SecretStorage` protocol, so a host app can supply its
own keychain wrapper or access group. `InMemorySecretStorage` is provided for
tests and previews.

---

## Widgets

A widget extension is a separate process and can't safely open the SwiftData store
mid-timeline, so the app writes a small `Codable` snapshot to a shared App Group
and the widget reads it.

```swift
// In the app, after any change worth surfacing:
store.publishWidgetSnapshot(appGroupIdentifier: "group.com.yourcompany.app")

// In the widget extension's TimelineProvider:
let snapshot = SharedSnapshotStore(appGroupIdentifier: "group.com.yourcompany.app")
    .currentSnapshot() ?? .placeholder

TrackerWidgetView(snapshot: snapshot, size: .medium)
```

Without an App Group the app runs fine and widgets simply never update —
`SharedSnapshotStore.isConfigured` tells you which situation you're in rather
than failing silently.

The library ships the widget **views** and the snapshot plumbing. It can't ship
the extension target itself; extensions have to live in your app project.

---

## Theming

This is the part that makes a rebrand cheap. Views never name a colour, a font
size, a corner radius or a gap — they ask the theme. Changing a brand's identity
is an assignment, not a refactor.

```swift
TrackerKitRootView()
    .trackerTheme(.standard.with {
        $0.palette = myBrandPalette
        $0.typography.displayFamily = "Söhne-Buch"
        $0.radii = .square
        $0.surfaces.control = .solid
    })
```

### The token groups

| Group | What it controls |
|---|---|
| `palette` | Colour by job: **brand**, categorical, sequential, diverging, status |
| `typography` | Type by **role** — `display`, `heading`, `body`, `label`, `numeric` |
| `spacing` | An 8pt grid plus a density multiplier (compact / comfortable / spacious) |
| `radii` | Corner radii, hardware concentricity, action shapes |
| `surfaces` | How the control layer and the content layer are drawn |
| `metrics` | Chart mark geometry — stroke widths, marker sizes, ring thickness |
| `motion` | Durations and spring bounce |

Two of these deserve a note.

**Typography is role-based, not size-based.** A brand face is one assignment
(`displayFamily`), and everything keeps scaling with Dynamic Type because custom
faces go through `Font.custom(_:size:relativeTo:)`. The `label` role maps to
`.footnote` rather than `.caption` on purpose — caption is already small and
caption2 is smaller still, and defaulting to them is how interfaces end up
unreadable at arm's length.

**Surfaces split the interface in two,** and the split is load-bearing. Liquid
Glass is a *navigation-layer* material: it samples what sits behind it, so it
works when it floats over content and turns to mush when it *is* the content.
`surfaces.control` governs toolbars, tab bars and floating actions;
`surfaces.card` governs everything the user is actually reading. Glass never
touches a content card in this library, and it drops to an opaque surface
automatically under Reduce Transparency.

### Brand colour is not a data colour

These were the same variable until they obviously shouldn't have been. The
categorical palette is engineered for exactly one job: eight hues maximally
separated in OKLab so a colourblind reader can tell series apart. That is the
opposite of what a brand palette wants, which is **one dominant colour and a
sharp accent**. Maximally-separated hues produce a rainbow, and a rainbow always
reads as a system default rather than a product.

`palette.brand` is now its own system — `accent`, `deep`, `onAccent` — and
`theme.accent` reads from it. The categorical palette governs multi-series charts
only, where its validation is a correctness requirement rather than a style
choice.

### Identity: hue, or intensity

Tracker colours are *persisted data*, assigned once at creation and stable
thereafter. That stability is right for identity — and it is also why a theme
alone could not make the app monochrome, since the hues live in the database.
`palette.identityMode` is the seam:

| Mode | Behaviour |
|---|---|
| `.categorical` | Each tracker keeps its own stored hue |
| `.brandMonochrome` | Hue is discarded at render time; trackers separate by *intensity* on the brand ramp |

Storage keeps its hue either way; the theme decides whether to render it.

### Shipped themes

Four presets, same views and same data, built only from token differences:

| Theme | Direction |
|---|---|
| `.nocturne` ★ | **The shipped identity.** Dark-first, teal monochrome, tight display tracking, filled cards. Single-appearance by choice |
| `.standard` | Cool neutrals, glass control layer, rounded display type, concentric corners. Neutral by design — reach for this if you'd rather bring your own |
| `.editorial` | Serif throughout, squared corners, flat outlined cards, no glass, spacious |
| `.vivid` | Compact, soft corners, glass-forward, springy motion. Built for a kid tapping fast on a shared iPad |

`TrackerKitConfiguration` defaults to `.nocturne`. The others are kept and
supported — pass any of them to `theme:`.

**Nocturne's idea is one sentence: the app is one colour; colour means status.**
Chrome, rings and single-series charts all sit in one teal family against a cool
near-black, so anything green, amber or red on screen is information rather than
decoration. Teal was chosen partly for distance from the status palette — brand
against status-good measures ΔE 23.0, where an amber or green brand would have
impersonated a verdict.

It declares `preferredColorScheme = .dark` and does not adapt to light, because
half its character is the near-black ground. That is a deliberate identity
choice, and it does override the viewer's own light/dark preference — so an app
that must respect that setting should use `.standard`, which is designed for
both. A theme built for both appearances must never force one.

The hero carries ambient information as well as brand: two offset radial blooms
over the surface, the second tinted by the **worst status across every goal**. It
warms toward amber and red when something needs attention and stays cool when it
doesn't, so you register the state of things before reading a number.

### The palette

Colours are assigned by the **job** they do, never picked per chart. Status
colours are reserved and never reused as a series colour.

The default categorical order is colourblind-validated in both appearances:

| | Light | Dark |
|---|---|---|
| Worst adjacent CVD ΔE | 9.1 | 8.4 |
| Worst adjacent normal-vision ΔE | 19.6 | 19.3 |

(OKLab ×100; ≥8 CVD target, ≥15 normal-vision floor.)

Two consequences are baked into the views:

1. Three light-mode slots sit under 3:1 against the light surface, so charts ship
   **visible labels or a legend** — identity is never carried by colour alone.
   Every status badge pairs a colour with a glyph *and* a word.
2. For forms where any two series can appear side by side (3-D point clouds,
   small multiples), only the **first three slots** validate.
   `seriesCapForAllPairs` enforces it; past eight series, `capped(at:)` folds the
   tail into "Other" rather than inventing a ninth hue nobody can distinguish.

To use your own brand palette, replace the values in `ChartPalette.standard` and
re-run the validator against your own surfaces. The rest of the library reads
roles, not hexes.

## Performance

Three guards, asserted in `PerformanceTests`:

- Seeding ~1,100 entries: **< 2s** (was 5.25s before batching and record caching)
- Five full dashboard passes: **< 150ms**
- A 365-period history: **< 50ms**

What makes that hold:

- **`TrackerStore.performBatch`** — many writes, one save and one reload. Every
  mutating method saves and reloads on its own, which is right for a button tap
  and quadratic in a loop.
- **Derived-value caches** — dashboards read the same progress/streak/sparkline
  values several times per body pass. Caches are `@ObservationIgnored`, which is
  load-bearing: filling a cache from inside a view body would otherwise register
  as a mutation and kick off another render.
- **Single-sweep history bucketing** — `ProgressEngine.history` walks the entries
  once across all periods instead of filtering per period.

---

## Testing

```bash
xcodebuild -scheme TrackerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

75 tests in four groups:

- **Engine tests** — period maths, pacing bands, streak rules, goal resolution,
  aggregation, trends, formatting. All against a fixed UTC calendar so results
  don't move with the machine's locale.
- **Store tests** — CRUD, cascade deletes, goal versioning, batching, report
  building and escaping, widget snapshots.
- **PIN tests** — verification, lockout ladder, salting, and an assertion that the
  PIN never appears in storage in the clear.
- **Render smoke tests** — every public visual forced through `ImageRenderer`,
  including degenerate input (empty, single-point, all-zero series) and an
  entirely empty profile. A view that compiles can still trap at runtime; this is
  what catches it. It already caught one: `RectangleMark` in `Chart3D` compiles
  against an `(x, y, z)` initializer and then traps demanding two extents.

---

## Demo app

`Demo/TrackerKitDemo.xcodeproj` — open and run. It's ~30 lines; every screen comes
from the library. Seeded with three profiles and ~120 days of deterministic
history, so it looks identical on every launch.

Two environment variables for jumping straight to a screen:

```bash
TKDEMO_PROFILE=Alex      # skip the profile picker
TKDEMO_TAB=gallery       # today | gallery | settings
```

---

## Known limits

- **Widget extension not included.** The views and snapshot plumbing are here; the
  extension target has to be created in your app project.
- **No sync.** Single device. The store is App Group–scoped at most.
- **No HealthKit import.** Entries come from the UI or your own code.
- **`.total` cadence goals aren't stoplit.** Without a deadline there is no such
  thing as "behind", so they read green when met and neutral otherwise.
- **Glass cannot be captured offscreen.** `glassEffect` is composited at display
  time, so an `ImageRenderer` or detached-window snapshot drops it — and a
  `GlassEffectContainer` can blank its whole subtree. Screens with glass have to
  be verified on a running simulator. The catalog generator notes this, and
  `TKDEMO_DETAIL` exists to get you onto a glass screen directly.
- **The 3-D native style draws points, not columns.** `RectangleMark` traps at
  runtime for a single (x, y, z), so `Chart3DStyle.native` uses `PointMark`.
  `.columns` (the default) is the hand-rolled renderer.
- **Demo app runs in-memory** by default so it resets each launch. Flip
  `inMemory: false` for a real persistent store.
