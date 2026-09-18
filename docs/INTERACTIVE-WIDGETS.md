# Interactive widgets — notes before we build

Written during the display-widget build, 2026-09-18. **Nothing here is built.**
This is the material for the blue/red team pass, not a plan that's been agreed.

The display widget works and is deliberately read-only. Everything below is what
changes the moment a widget can *write*.

---

## Why it's worth doing at all

The friction of unlocking, finding the app and opening it is what kills habit
logging. A "did it" button on the Home Screen, Lock Screen or in Control Centre
removes most of that. For a tracker aimed at kids on a shared device, it is
plausibly the single highest-value feature left in the project.

That's the case *for*. The rest of this document is the cost.

---

## The architectural change

Today the data flows one way:

```
app ──writes snapshot──► App Group ──reads──► widget
```

The widget never touches the SwiftData store. It reads a ~1.2 KB JSON blob and
renders it. That's why it is safe.

Interactive logging inverts part of that:

```
widget ──AppIntent──► writes an Entry ──► SwiftData store ◄── app also writes
```

**Two processes now write to the same store.** That is the whole problem, and
everything below follows from it.

### What specifically breaks

1. **`TrackerStore` assumes a single writer.** It caches derived values
   (`progressCache`, `streakCache`, `dailyCache`, `historyCache`, `entryIndex`)
   and invalidates them on its *own* mutations. A write from the extension
   invalidates nothing in the app's copy. The app would show stale progress
   until something else happened to reload it.

2. **The store must move into the App Group container.** `TrackerKitSchema.container`
   already accepts `appGroupIdentifier`, so this part exists — but the demo
   currently runs `inMemory: true`, so the on-disk path has **never been
   exercised**. That has to be fixed first regardless; see the open items.

3. **SwiftData concurrent access across processes is not a solved problem the
   way it is for a single app.** Needs a decided answer, not an assumption:
   - Does the extension open its own `ModelContainer` on the same store file?
   - What happens on simultaneous writes from app and extension?
   - Is a write-ahead queue in the App Group (extension appends an intent, app
     drains it) safer than two live containers?

   The queue option is worth taking seriously. It keeps a single writer, which
   preserves every assumption the store currently makes.

4. **Cache invalidation across processes.** Even with a queue, the app needs to
   know something arrived. Darwin notifications (`CFNotificationCenter`) are the
   usual mechanism. `WidgetCenter.reloadAllTimelines()` covers the other
   direction.

5. **Widget budget.** WidgetKit throttles reloads. An interaction triggers an
   immediate reload, but a chatty implementation gets its budget cut and the
   widget goes stale — which is worse than not being interactive.

---

## Red-team prompts

Things to attack in the review, phrased as failure modes rather than features.

**Correctness**
- Double-tap on the widget while the app is open: two entries, or one?
- Tap at 23:59:58; the write lands at 00:00:01. Which day does it count for, and
  does the streak agree with the user's belief?
- Widget shows yesterday's snapshot (timeline not yet refreshed), user taps
  "done" — does it log against the day shown, or today?
- Extension writes while the app is mid-`performBatch`. What does the app see?
- Store is in the App Group; user deletes the *app* but the container survives —
  what's the state on reinstall?

**Security and privacy**
- The PIN gates *profile switching in the app*. A widget on the Lock Screen
  shows one profile's data **with no gate at all**. On a shared family iPad this
  may be exactly wrong. Which profile does the widget show, who decided, and can
  a child see a sibling's data by adding a widget?
- Interactive logging from the Lock Screen means logging **without
  authentication**. Is that acceptable? It probably is for "drank water"; it
  probably isn't for anything a kid would want to falsify.
- The App Group container is readable by every target in the group. Fine today;
  worth restating if more extensions appear.

**Data integrity**
- Is an `AppIntent` write idempotent if the system retries it?
- What happens if the tracker referenced by the widget was deleted or archived
  between snapshot and tap? (The display widget already tolerates this — the
  deep link resolves to nothing and lands on the dashboard. A *write* must be at
  least as careful.)
- Goal versions are append-only. Does a widget write ever need to create one? It
  must not.

**Failure and recovery**
- App Group unavailable (device locked, data protection). `SharedSnapshotStore`
  degrades to placeholder today. What does a *write* do — fail silently, queue,
  or surface an error the user can't see?
- Extension crashes mid-write. Is the store left consistent?

---

## Smaller decisions to settle in the same pass

- **Which surfaces?** Home Screen interactive widget, Control Centre
  `ControlWidget`, Action Button, Lock Screen. They have different auth and
  budget characteristics; they are not one feature.
- **What can be logged?** Checkbox trackers map cleanly to one tap. Count and
  duration need a value — a `+1` default, or an intent with a parameter?
- **Undo.** A mis-tap on a widget is easy and currently has no remedy without
  opening the app.
- **Which profile?** See the security note above. This needs an explicit answer
  before any code.

---

## Where the code will need to change

Concrete list, so the review has something to point at.

| File | Change |
|---|---|
| `Store/TrackerStore.swift` | Cross-process invalidation; revisit the cache design; possibly a queue drain on launch/foreground |
| `Model/Records.swift` | `TrackerKitSchema.container` already takes an App Group — needs real-world exercise, and a decision on one container or two |
| `Widgets/WidgetSnapshot.swift` | Snapshot gains whatever the intent needs to be idempotent (an entry id, a day stamp) |
| New: `Widgets/LogIntent.swift` | The `AppIntent` itself, in the library so both targets share it |
| `Demo/TrackerDashWidgets/` | Intent wiring, interactive controls |
| `Demo/TrackerKitDemo/` | `inMemory: false` — the on-disk path must be real before any of this |

---

## The recommendation going in

Do **not** build interactive logging on top of two live SwiftData containers
because it's the obvious implementation. Take the write-ahead queue seriously
first: the extension appends an intent record to the App Group, the app drains
it and remains the only writer. It keeps every assumption the store already makes
and turns a concurrency problem into a much smaller ordering problem.

That is a position to be argued with, not a decision.
