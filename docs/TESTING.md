# Testing TrackerKit

Who tests what, and why it takes two tools.

---

## The short version

**Claude Code can run the simulators** — boot them, install, launch, deep-link to
any screen, screenshot, record video, flip light/dark, change Dynamic Type, and
drive real taps through XCUITest. Most testing needs nobody else.

**What Claude Code cannot do is show you a window.** Neither Xcode install on
this machine ships `Simulator.app`:

```
/Applications/Xcode-27.app/Contents/Developer/   # Library Makefiles Platforms
                                                 # Toolchains Tools usr
                                                 # ← no Applications/
```

Only the CoreSimulator runtime and `simctl` are present. So simulators run
*headless*: real devices executing real code, observed through screenshots and
video rather than a live window.

That leaves exactly one gap, and it is worth being precise about it, because it
is smaller than it sounds:

| | Claude Code | Needs Cowork / a person |
|---|---|---|
| Does the tap land? | yes — XCUITest | |
| Does it look right? | yes — screenshot | |
| Does the animation look right? | yes — video capture | |
| Does it *feel* right? | | yes |
| Poking around with no plan | | yes |
| Following a hunch mid-session | | yes |

Automation answers questions you already thought to ask. A person at a live
simulator finds the ones you didn't. **Exploratory testing is the gap** — not
"running the simulator".

---

## Part 1 — What Claude Code checks (ask for any of it)

### The two suites, and why the split matters

```bash
# Unit — 110 tests. Proves views DRAW.
xcodebuild test -scheme TrackerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# UI — 12 tests. Proves taps LAND.
cd Demo && xcodebuild test -project TrackerKitDemo.xcodeproj \
  -scheme TrackerKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TrackerDashUITests
```

> **`swift test` does not work here** and this is not a bug to fix. It builds for
> macOS, where `MessageUI` doesn't exist, and fails in the export composer. Always
> go through `xcodebuild` with a simulator destination.

The split is load-bearing. A quick-log button that silently did nothing passed
the **entire** unit suite — every view drew perfectly, and the tap hit a
`NavigationLink` wrapped around it. That is why the UI target exists. When you
add a feature, ask which suite would have caught it breaking; if the answer is
neither, that's the test to write.

### Accessibility audit

`AccessibilityAuditTests` runs Apple's own auditor over the dashboard, gallery,
and wizard. It catches what a screenshot can't: hit regions under 44pt, contrast,
clipped text, and fixed font sizes that ignore Dynamic Type.

```bash
cd Demo && xcodebuild test -project TrackerKitDemo.xcodeproj \
  -scheme TrackerKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TrackerDashUITests/AccessibilityAuditTests
```

It passes, but not because the app is clean — the four categories we already know
about are listed in `knownIssues` at the top of that file and ignored, so a red
run means a **new** problem rather than the familiar red everyone learns to
scroll past. The known four are in *Known open items* below. Delete one from that
set once it's fixed and the test starts guarding the category properly.

Read contrast findings sceptically: the auditor judges contrast by sampling the
backdrop behind a label, and gets it wrong over glass and gradients, which this
theme leans on. Confirm any contrast hit against the theme tokens before acting
on it.

---

## Part 2 — Demo routes (the part worth stealing)

The demo app reads environment variables to open straight onto one screen. This
is how to get to a state in two seconds instead of forty taps — useful to Cowork
and to a person driving Xcode by hand alike.

| Variable | Value | Opens |
|---|---|---|
| `TKDEMO_PROFILE` | `Alex` \| `Jordan` \| `Sam` | Skips the picker, straight to that profile |
| `TKDEMO_TAB` | `today` \| `gallery` \| `settings` | Opens on that tab |
| `TKDEMO_DETAIL` | a tracker name | That tracker's detail screen |
| `TKDEMO_ONBOARD` | `1` | Empty profile — the first-run wizard |
| `TKDEMO_FRESH` | `1` | **Cold start**: no profiles at all, welcome screen |
| `TKDEMO_SEEDLAYOUT` | `1` | A customised dashboard, already arranged |
| `TKDEMO_THEME` | `nocturne` \| `vivid` \| `editorial` \| `standard` | Swaps the whole identity |

The three seeded profiles differ on purpose: **Alex** is the full set with a
breached limit and a broken streak, **Jordan** is lighter, **Sam** is sparse.
Test against Alex — it's the one with the awkward data in it.

**From the command line:**

```bash
xcrun simctl install "iPhone 17 Pro" /path/to/TrackerKitDemo.app
env SIMCTL_CHILD_TKDEMO_FRESH=1 \
    SIMCTL_CHILD_TKDEMO_THEME=nocturne \
    xcrun simctl launch --terminate-running-process \
    "iPhone 17 Pro" com.mightylodek.software.trackerdash
```

Note the `SIMCTL_CHILD_` prefix — that is how a variable reaches the app rather
than stopping at `simctl`. Getting this wrong launches a perfectly normal-looking
app on the default route and quietly wastes an afternoon.

**In Xcode:** Product → Scheme → Edit Scheme → Run → Arguments → Environment
Variables. No prefix there; just `TKDEMO_FRESH` = `1`.

**Useful simulator controls:**

```bash
xcrun simctl ui "iPhone 17 Pro" appearance dark          # or light
xcrun simctl ui "iPhone 17 Pro" content_size accessibility-extra-extra-large
xcrun simctl io "iPhone 17 Pro" screenshot out.png
xcrun simctl io "iPhone 17 Pro" recordVideo --codec h264 out.mov   # ^C to stop
```

---

## Part 3 — For Cowork: the exploratory pass

Everything above is automated. **Do not re-run it by hand.** Your job is the
part automation is bad at: judgement, feel, and the bugs nobody predicted.

### Setup

Open the project in Xcode, pick a simulator, set the scheme environment
variables from the table above, Run. Test **iPhone 17 Pro** and **iPad Pro
11-inch (M5)** — the layout adapts between them and the iPad path gets far less
attention.

### What to actually look for

**1. The first run (`TKDEMO_FRESH=1`)**
This is the only impression a new user gets once. Welcome → Create a profile →
wizard → dashboard. Does it feel like a setup flow or an interrogation? Does any
screen leave you unsure what to do next? Is there any point where you'd put the
phone down?

**2. Logging, which is the whole app**
The core loop is *notice a thing → log it in one tap*. Open Alex, log several
things across several trackers. Count the taps. Anything that takes more than one
tap to log a routine thing is a design bug, not a nitpick.

Specifically try to break undo:
- Double-tap `+` by accident. Can you get back?
- Tap `+`, wait for the undo offer to expire (6s), then decide you wanted it undone.
- Tap `+` on one tracker, then immediately `+` on another. Which does undo reverse?
  Is that what you expected?

**3. The iPad**
Rotate. Split-screen it against Safari. Both orientations, both split widths. The
dashboard is a `LazyVStack` in a scroll view and wide layouts are where that kind
of thing falls apart.

**4. Dynamic Type and dark/light**
Settings → Accessibility → Display & Text Size → Larger Text, slide to maximum.
Walk the dashboard, a detail screen, and the wizard. Look for clipped labels,
numbers colliding with their own captions, buttons that stop being tappable.
Then flip light/dark and repeat the dashboard. Nocturne is a dark-first theme —
light mode gets the least attention and is the likeliest to be wrong.

**5. VoiceOver**
Turn it on. Can you log a tracker without looking? Do the charts announce
anything useful, or just read as a wall of unlabelled elements? This is the one
Claude Code genuinely cannot assess — the auditor checks that labels *exist*,
not that they make sense in sequence.

**6. The gallery**
Every visual, on both devices. Numbers that overlap, charts that clip at the
edges, anything that renders empty. The 3D chart is the fragile one — it has
already trapped at runtime once, in a form that compiled cleanly.

### What to ignore

- **Data resets every launch.** The demo runs in-memory on purpose. Not a bug.
- **Anything labelled PLACEHOLDER.** Deliberate and loud by design.
- **Widgets not updating in the simulator.** Expected; the App Group snapshot path
  is verified on a real device.

---

## Part 4 — Known open items

Don't file these; they're already known. Do tell us if one is **worse in
practice** than it sounds on paper — that's genuinely useful.

- **`textMuted` is 3.88:1** against both dark surfaces, under the 4.5 needed for
  normal-size text (fine for large). The only genuine contrast failure in the
  palette — `textPrimary` is 15.8:1 and `textSecondary` 8.2:1, both comfortable.
- **Four audit categories are suppressed** in `AccessibilityAuditTests.knownIssues`
  and not yet worked through: contrast (above), fixed font sizes that ignore
  Dynamic Type, clipped tracker titles, and hit regions under 44pt (the Archived
  switch, and the heatmap cells below).
- **Heatmap cells are 13pt** — far under the 44pt minimum. A deliberate trade for
  the calendar view; revisit if it bites in use.
- **The hero card is tall**, so on a smaller phone the first tracker row starts
  near the bottom of the screen.
- **On-disk persistence has never been executed.** The demo is in-memory only, so
  the real SwiftData path — and any migration — is completely untested. This is
  the biggest open risk in the project and it blocks interactive widgets.
- **No watch app yet.** See `WATCH.md`; it needs to run standalone.

---

## Part 5 — Reporting back

What makes a report actionable, roughly in order of value:

1. **The route.** `TKDEMO_PROFILE=Alex TKDEMO_TAB=gallery`, device, orientation.
   Without this a bug can take longer to find than to fix.
2. **What you did, in taps.** "Tapped + on Water three times fast."
3. **What happened vs. what you expected.** Both halves — the gap between them is
   often the actual bug.
4. **A screenshot or screen recording.** Cmd-S in Simulator; recordings for
   anything involving animation or timing.
5. **Whether it reproduces.** Once is a report. Twice is a bug. Never again is
   worth saying too, because that's usually a race condition and those are the
   ones that reach users.

Drop findings in `claude_workspace/team_inbox/` or say them directly. A one-line
"this felt wrong and I can't say why" is worth filing — that instinct is the
entire reason a person is in this loop.
