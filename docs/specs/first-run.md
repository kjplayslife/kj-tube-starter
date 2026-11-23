# First run
Status: approved (KJ, 2026-11-13: "go with what you got", to try on KJ Tube Dev)

## Summary
The first time the app is opened, it walks the person through four short steps, then loads the first Inbox: bring in creators, pick the daily amount, rank them, and a quick "ready?" check. It uses the screens that already exist (the import list and the Following page) and adds only a welcome, one small sheet for the daily amount, a bar on Following, and the check. It serves "trusted creators only": the first Inbox comes from an order and an amount the person chose on purpose, not from defaults.

Why it is needed: today the first Inbox loads the moment the person comes back from following someone (D16). After an import of 40 creators that means the first videos are picked in A to Z tick order at 30 minutes, before anything was ranked or set.

## Decisions (D175)
- KJ took every suggested option: guide through the real screens, hold the first Inbox, a small sheet for weekday and weekend minutes, and a short summary as the check.
- First run is **over once the first Inbox has loaded**, and never shows again. Anyone who already has creators or has been served a video (KJ's own phone) never sees it.
- The first Inbox **waits for "Load my Inbox"** (changes D16). Starter videos (D79) are still fetched at follow time, so loading is instant.
- Minutes picked during first run **don't start the weekly loosen clock** (D145): nothing has been loosened yet. The clock rules apply from the first Inbox on.
- Import is offered first, but **searching by hand is always allowed**. One creator is enough to go on.
- Per-creator settings get **no screen of their own**: one line on the Following bar says to swipe a creator right for Watch in Order or Any Length (D172).
- ⚙︎ Defaults: no skip button for the amount sheet (Continue keeps 30 / 60); no progress dots; no way to run first run again short of deleting the app.

## Behavior
**1. Welcome** (the Inbox, no creators yet; replaces today's welcome, D28)
- "Welcome to KJ Tube", the same one line as today, then **Import from YouTube** (main button) and **Find creators myself** (opens Following with the keyboard up, D137).
- A build with no Google client ID shows only Find creators (D152).

**2. Creators**
- Import: the existing sign-in and pick list, unchanged. Continue follows the picks.
- By hand: the existing search on Following.

**3. Daily amount** (a small sheet)
- Shows right after the import's Continue. Following by hand, it shows when Load my Inbox is tapped, just before the check, so it never pops up in the middle of a search.
- "How much content per day?" with two rows, **Weekdays** and **Weekends**, the same 30 / 60 / 90 choices as Settings, starting at 30 and 60, and a **Friday is weekend** switch, off to start (D146). One line under: "You can tighten this any time. Loosening is allowed once a week."
- **Continue** closes it and lands on Following. Swiping it away is the same as Continue.

**4. Rank and per-creator settings** (the Following page itself)
- A bar pinned above the tab bar while first run is on: "Hold and drag to rank. Top creators come first. Swipe a creator right for Watch in Order or Any Length." and a blue **Load my Inbox** button. In Random order the ranking sentence is left out.
- It shows once at least one creator is followed, and hides while searching. It replaces the 5-second "N creators added" bar (D158) during first run only.
- Everything on Following works as usual: search, import more, drag, swipe, ⓘ.
- The Inbox tab during first run shows "Almost ready" with **Load my Inbox** and **Rank creators** instead of loading.

**5. The check** (a small sheet from Load my Inbox)
- "Ready for your first Inbox?"
- "30 min on weekdays, 60 on weekends" (plus "Friday counts as weekend" when that switch is on) with a **Change** link back to the amount sheet.
- "12 creators. First up: A, B, C."
- If any: "Watch in Order: X. Any Length: Y."
- **Load my Inbox** (blue) and **Keep editing**.
- Load my Inbox ends first run, switches to the Inbox and serves the first shipment by the normal rules.

**States**
- App closed mid-way: it reopens where the person was (the step is worked out from what is saved: creators or not, amount picked or not).
- Everyone unfollowed during first run: back to the welcome.
- Starters still loading or failed at Load my Inbox: the existing "Getting today's videos…" and retry rules (D105, D106) apply.
- Nothing eligible from anyone: the existing "No new videos from your creators" screen.

**What is saved**
- Two small flags: amount picked, first run done. No new data model.

**Trying it on KJ Tube Dev**
- Settings in KJ Tube Dev has a red **Start over (first run)** row at the bottom. It empties Dev (creators, videos, settings) and shows first run again. The real KJ Tube never has this row.

## Acceptance criteria
- [ ] AC1 A fresh install opens on the welcome with Import from YouTube and Find creators myself; with no client ID only Find creators shows.
- [ ] AC2 The daily amount sheet shows once, starting at 30 / 60: after the import's Continue, or else on the first tap of Load my Inbox, before the check.
- [ ] AC3 Minutes set on that sheet are the ones in Settings afterwards, and Settings shows no weekly lock for them.
- [ ] AC4 During first run, opening the Inbox tab does not serve videos; it shows "Almost ready" with both buttons.
- [ ] AC5 Following shows the bar with Load my Inbox for as long as first run is on, and not the "N creators added" bar.
- [ ] AC6 The check shows the chosen minutes, the creator count, the top three in the current order, and the names with Watch in Order or Any Length.
- [ ] AC7 Keep editing returns to Following with nothing served. Change opens the amount sheet and comes back to the check.
- [ ] AC8 Load my Inbox serves the first shipment using the rank, minutes and per-creator settings as they are at that moment, and lands on the Inbox.
- [ ] AC9 After that, none of the first-run screens or bars show again, also after a relaunch.
- [ ] AC10 An install that already has creators or served videos never shows first run after updating.
- [ ] AC11 Quitting the app at any step and reopening returns to that step with nothing lost.
- [ ] AC12 After first run, a raise of the minutes asks to confirm and starts the 7-day clock as usual.

## Out of scope
- Explaining the player, refreshes, Skip Ad or the mini player.
- Asking shipment time, refreshes, Ranked / Random or Friday is weekend (all stay in Settings).
- Changes to the import list or the Following rows themselves (another thread owns the rows, D171).
- Running first run again from Settings.

## Notes for the build
- The Following row changes (swipe right for the two switches, D172 to D174) are merged in. This feature adds the bar and touches no row code.
- Engine: a "first run" gate in front of `shipNow`, with unit tests. Views stay thin.

## Test plan
- Unit: the step is derived correctly from saved state (no creators, creators and no amount, amount picked, done); the gate blocks `shipNow` and scheduled shipments until done; existing installs count as done; first-run minute changes set no lock; the summary text (top three, fewer than three, Random order, switches on or off).
- Simulator: fresh install walk-through by hand follow (AC1, AC2, AC4 to AC9, AC11); an install with data updates without seeing it (AC10). The import path (needs KJ's Google account) on KJ's phone.
