# Device test plan

Ten checks covering what no simulator, unit test or screenshot can reach.
Ordered by risk. Designed version (with progress tracking):
https://claude.ai/code/artifact/88497323-36c6-47d8-aa4a-a5c4b0bb9704

**Build under test:** TrackerDash 1.0, `com.mightylodek.software.trackerdash`,
commit `3913049`, on-disk storage.

## Already covered — don't re-test

110 unit + 17 UI tests run on every change and already prove: quick-log changes
the number, the `+` survives repeated taps, undo reverses a double-tap and
expires after 6s, the wizard presents and creates trackers, skip doesn't loop,
cold start reaches a populated dashboard, logged data survives kill-and-relaunch,
and every chart renders including with empty and all-zero data.

## P1 — code that has never run

These three paths have executed **zero times, anywhere**. The suite substitutes
fakes for all three because the real thing needs entitlements, a Mail account, or
the passage of time.

**1. Keychain & PIN.** The SPM test bundle has no keychain entitlement, so every
PIN test runs against `InMemorySecretStorage` — a dictionary. `KeychainStore` has
never been exercised. Set a PIN, force-quit, reopen, verify it's demanded; enter
a wrong PIN four times and confirm the lockout ladder; **reboot** and verify the
PIN still holds. If it works before a reboot but not after, it never reached the
Keychain. *Locked out for real? Delete and reinstall clears it.*

**2. Persistence over time.** In-memory until today; I've proved a 30-second
kill-and-relaunch works, which says nothing about an overnight gap, a reboot, or
iOS purging the app under memory pressure. Log recognisable values, force-quit,
reboot, then **leave it overnight** and check. Log daily for a few days and
confirm the streak climbs rather than resetting. Watch for demo data reappearing
as if new — that means seeding ran over real entries. *Start this first; it runs
in the background while you do the rest.*

**3. Export composer.** MessageUI cannot run in the simulator at all. This was in
the original brief and has never been opened end to end. Export by email: does a
compose sheet appear, is the attachment really attached, does the report render
when it arrives? Repeat for text. Cancel a sheet halfway and confirm the app
recovers. Expect roughness.

## P2 — things the simulator renders dishonestly

**4. Widget refresh.** Timeline reloads fire on a different schedule on device,
and the App Group snapshot path is the kind that works until it silently doesn't.
Add small, medium and large (different layouts, not one scaled). Log something,
return to the home screen, check after minutes and after an hour. Add to the lock
screen and check StandBy. Placeholder text or a never-updating widget usually
means the App Group isn't wired through on device.

**5. Widget deep links.** Cold-launch routing — app not running, has to boot,
restore a profile and route — only really happens on device. Force-quit, tap a
specific row in the medium/large widget, confirm it opens *that tracker*. Repeat
with a different row. **With a PIN set, confirm a widget tap is still gated** —
a bypass here is a security issue.

**6. Liquid Glass.** `glassEffect` is composited at display time and is absent
from every offscreen render — proven with a probe where a solid capsule drew and
an identical glass one didn't. **Every screenshot produced so far has the glass
layer missing.** Look at the floating action bar and tab bar with content
scrolling behind them; check the undo bar doesn't fight the action bar. Judge
legibility over both light and dark content. Taste matters more than criteria
here — be blunt.

## P3 — feel, and what automation can't judge

**7. Haptics.** No Taptic Engine in the simulator, so this is entirely invisible
to me, including whether any exist. Does an ordinary log tick? Does completing a
goal feel different? Does breaching an `.atMost` limit feel different again?

**8. Scroll, animation, heat.** The simulator runs on the Mac's GPU. Scroll the
dashboard hard, walk the whole Gallery, rotate the 3D chart (the most expensive
thing in the app), then sit in the Gallery a few minutes and check for warmth —
warmth means something redraws continuously.

**9. VoiceOver.** The auditor confirms labels *exist*; it can't tell whether they
make sense read aloud in sequence. Can you log something with the screen off? Do
rows announce value *and* target? Then max out Larger Text and walk the dashboard
and wizard.

**10. Known defects — worse than they sound?** Already logged and suppressed in
the accessibility gate; I need them ranked by real annoyance so I fix them in the
right order. 13pt heatmap cells (try tapping a specific day), clipped tracker
titles, numerals that ignore Dynamic Type, the sub-44pt Archived switch, and the
tall hero pushing the first row down the screen.

## Reporting back

```
#         which check, e.g. 04 widgets
Did       added the medium widget, logged water, went home
Saw       widget still showed the old number after 20 minutes
Expected  it to catch up
Again?    yes, twice
Shot      IMG_4021.mov
```

A screen recording beats a description for anything involving timing or
animation. Something that happened once and never again is still worth saying —
intermittent bugs are the ones that reach users.
