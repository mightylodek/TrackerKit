# watchOS — notes toward a standalone watch app

Written during the display-widget build, 2026-09-18.

> **Step 1 is done (2026-09-19).** The package declares `.watchOS(.v26)`, builds
> for watchOS, and **109 of its 110 tests pass on an Apple Watch simulator.** The
> core is portable — that is now measured, not assumed. Steps 2–4 below are still
> unbuilt. See *What step 1 actually cost* before starting step 2.

## The requirement that changes everything

> "ideally standalone on the watch as well since my kids don't have phones to
> connect to, just their watches"

This is not "add a watch companion". A companion app assumes a paired iPhone
running the real app, with the watch as a remote control. If the kids have no
phones, the watch **is** the device: it owns the data, does the logging, computes
the streaks, and never syncs to anything.

That reframes it from a UI port to a second first-class platform, and it should
shape decisions now rather than being retrofitted.

---

## What step 1 actually cost

The estimate below was close on the shared layer and wrong about the UI. The real
shape of the work, for the record:

| | Predicted | Actual |
|---|---|---|
| Shared files needing a watchOS path | 3–4 | **1** (`Color+Hex.swift`) |
| Framework-gated files | 1 (`MessageUI`) | **1**, as predicted |
| UI files needing exclusion | not considered | **15** — the whole `UI/` directory |
| Charts needing exclusion | "triage later" | **1** (`Chart3DView`) |

The surprise was that the UI layer had to come out wholesale rather than being
patched. Twelve compile errors across five files — `Menu`, `.segmented`,
`editMode`, `keyboardType`, `UIApplication` — but every one of them sat in a
screen designed for a phone, so guarding individual call sites would have
produced watchOS builds of views nobody should ever put on a watch. The whole of
`Sources/TrackerKit/UI/` is now behind `#if os(iOS)`.

`KeychainStore` needed no change, as predicted. `PDFReportRenderer` compiled
untouched — `ImageRenderer` is available on watchOS after all.

**The boundary is now a rule, not a coincidence:** anything under `UI/` is
iOS-only and may use whatever it likes; anything under `Model/`, `Engine/`,
`Store/`, `Theme/`, `Security/` and `Widgets/` must compile for both. The
watchOS test run is what enforces it.

```bash
xcodebuild -scheme TrackerKit -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' build
xcodebuild test -scheme TrackerKit -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
```

One drift was found on the way in: `ExportSettingsView` had picked up
`UIApplication.openSettingsURLString` since these notes were written — exactly
the creep this step was meant to stop. A week cost one file.

---

## The good news: the library is mostly portable already

I checked rather than assumed. Of 58 source files, only **four** import a
platform-locked framework, and only **three** use meaningfully iOS-only API:

| File | Uses | Status on watchOS |
|---|---|---|
| `Export/ComposerViews.swift` | `MessageUI`, `UIViewControllerRepresentable` (23 refs) | **Unavailable.** Mail/SMS composers don't exist on watchOS |
| `Theme/Color+Hex.swift` | `UIColor` dynamic provider (5 refs) | Needs a watchOS path — no `UIColor` trait-based provider |
| `Export/PDFReportRenderer.swift` | `UIGraphics`, `ImageRenderer` (2 refs) | `ImageRenderer` exists; PDF context needs checking |
| `Security/KeychainStore.swift` | `import Security` | **Available on watchOS.** No change expected |

Everything else — the engines, `TrackerStore`, SwiftData, Swift Charts, the theme
and token system, the widget snapshot layer — is portable in principle.

**The five engines are the real asset here.** They're pure value-type code with
no SwiftUI or SwiftData dependency, which was a deliberate choice and pays off
exactly here.

---

## What has to happen

1. **`Package.swift` gains `.watchOS(.v26)`.** This will immediately fail to
   compile until the four files above are conditionalised. That's the first,
   mechanical piece of work.

2. **Conditional compilation, not deletion.** `#if canImport(UIKit)` around the
   composer views; a watchOS branch for the dynamic colour provider. Export drops
   to share-sheet/file only on the watch — there is no Mail composer to fill in.

3. **A separate watch UI, not the iPhone views shrunk.** The dashboard, gallery
   and detail screens assume a phone-sized canvas. What a watch needs is:
   - a glanceable "what's left today"
   - one-tap logging for checkbox trackers
   - a crown-driven value picker for counts and durations
   - complications (the watch equivalent of the widget — the snapshot layer
     already models exactly this)

4. **Standalone means standalone.** No `WCSession`, no paired-phone assumption.
   The watch app owns its own SwiftData store. If a phone ever appears later,
   sync becomes a genuine design problem — but it is explicitly *not* one now,
   and building for it now would be speculative.

---

## What the standalone requirement implies that's easy to miss

- **Profiles and PINs on a watch.** The multi-profile model exists because one
  iPad is shared. A kid's own watch is a single-user device — profiles may be
  unnecessary there, or may need to be a one-time setup choice rather than a
  gate on every launch. `PINManager` works on watchOS but a 4-digit PIN pad on a
  watch face is a poor interaction.
- **Export has no obvious home.** Weekly reports assume a composer. On a
  standalone watch there's no Mail app to hand off to. Either the watch doesn't
  export, or it needs a genuinely different delivery route.
- **Onboarding.** Creating a tracker with a title, goal, cadence and unit is a
  lot of text entry for a watch. Likely needs presets or dictation, or setup
  happens elsewhere — but "elsewhere" doesn't exist if there's no phone.
- **The charts need triage.** Swift Charts runs on watchOS, but a heatmap
  calendar or a 3-D field is meaningless at 45mm. The sparkline, rings, and
  mini progress bar carry over well; most of the gallery does not.
- **Nocturne is a good fit.** A dark-first, near-monochrome theme is exactly
  right for an OLED watch face, and the token system means it transfers without
  redesign.

---

## The screen, as specified by the owner (2026-09-24)

One habit per screen, swipe left or right for the next. Top to bottom:

1. **The visual** — a bar chart with a target line. Tapping it opens entry.
2. **"Add 10 Min"** — the prominent button, just below the chart. Scroll to it.
   The label is the habit's own quick-log step, so it reads "Add 10 Min" for
   Reading and something else for Water.
3. **"Print Report"** — produces the one-page report specified below.

**Reading is the default habit.**

Notice what this shape settles: there is no list, no dashboard and no navigation
stack on the watch. A habit is a page. That fits the crown and the swipe, and it
means `TrackerDashboardView` and everything under it stays on iOS, which is
already how the `#if os(iOS)` boundary is drawn.

## The watch report — one page, 8.5x11

Owner's spec, verbatim in substance. The person's name at the top, then:

| Block | Content | Notes |
|---|---|---|
| Last 7 days | Bar chart with total | x axis `M T W Th F Sa Su` |
| Last 30 days | Line chart with total | Titled. **No x-axis labels** |
| Last 6 months | Bar chart with total | x axis is the month abbreviation |
| Last 7 days | The data points themselves | The numbers, not a chart |

**All four fit on a single sheet.** That is the constraint, not an aspiration —
the existing `CustomReportPDFRenderer` composes pages tile by tile and already
knows how to hold four tiles on a portrait sheet, so this is a fixed layout
rather than a new engine.

What already exists for this: `CustomReportEngine` builds every one of those
ranges today (`.lastDays(7)`, `.lastDays(30)`, and a six-month range via
`.absolute`), `Formatters.weekdayInitial` gives the `M T W Th F Sa Su` labels,
and the monthly breakdown gives the six-month buckets. The renderer is iOS-only
but the engine is not, so a watch can *build* the report; whether it can print
one is a separate question — watchOS has no share sheet and no printer access
worth the name, so this likely hands off to the phone, or to a file the phone
picks up.

**That hand-off contradicts "standalone" and needs deciding.** If the kids have
no phone, "Print Report" on the watch has nowhere to send a PDF. Options are a
report that emails itself from the watch, a report that waits for a phone to
appear, or accepting that printing is a phone-only feature.

## One profile, no PIN (2026-09-24)

> "i think phone and watch both only need one profile. that way we don't need
> pin access. the biometrics to get into the device serve that purpose."

The reasoning is sound: a personal device is already gated by Face ID or a
passcode, and a second 4-digit gate inside it protects nothing a determined
child couldn't get past anyway. It also removes the worst interaction on the
watch — a PIN pad at 45mm.

**What this changes:** the profile picker, the PIN pad, the PIN setup flow, the
authority model and the device-passcode recovery all become dead weight on a
single-profile device.

**What it should not do is delete them.** The original requirement was a shared
iPad, and that hardware has not gone away. The right shape is a configuration
flag — single-profile by default, multi-profile available — so the iPad case is
one setting rather than a revert. Nothing is thrown away, and the tests that
cover the PIN work keep running.

## Suggested order, when we get to it

1. ~~Add `.watchOS(.v26)` and conditionalise the four files.~~ **Done
   2026-09-19.** Cost: one shared file changed, sixteen excluded.
2. Single-profile mode, which the watch needs before it needs anything else.
3. Build a standalone watch target with a single screen: today's trackers, tap
   to log.
3. Add complications off the existing `WidgetSnapshot`.
4. Only then consider whether profiles/PIN/export belong on the watch at all.

Step 1 was worth doing early because it stops iOS-only API creeping further into
the shared layer — and it had already cost one file in a week.

**Before step 2**, two things need deciding, and they are product questions
rather than engineering ones:

- **Does a kid's watch have profiles at all?** The multi-profile model exists
  because one iPad is shared. A personal watch is a single-user device. If the
  answer is no, `ProfileSession` stays on iOS and the watch talks to
  `TrackerStore` directly — which is simpler, and changes what step 2 looks like.
- **How does a tracker get created with no phone in the house?** Title, goal,
  cadence and unit is a lot of text entry at 45mm. The templates built for the
  iOS wizard are the obvious answer: pick "Youth sport", get four trackers, never
  type anything. That makes `TrackerTemplate` a watch asset, not just an
  onboarding convenience.
