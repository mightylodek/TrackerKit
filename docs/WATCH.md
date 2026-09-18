# watchOS — notes toward a standalone watch app

Written during the display-widget build, 2026-09-18. **Nothing here is built.**

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

## Suggested order, when we get to it

1. Add `.watchOS(.v26)` and conditionalise the four files — purely mechanical,
   and it proves the core is portable.
2. Build a standalone watch target with a single screen: today's trackers, tap
   to log.
3. Add complications off the existing `WidgetSnapshot`.
4. Only then consider whether profiles/PIN/export belong on the watch at all.

Step 1 is worth doing early even if the watch app is far off, because it stops
iOS-only API from creeping further into the shared layer. Every week it's
deferred, the port gets slightly more expensive.
