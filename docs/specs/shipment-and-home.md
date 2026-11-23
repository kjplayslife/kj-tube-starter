# Shipment engine + Home (Phase 3)
Status: approved

## Summary
The heart of the app: the pure-Swift `ShipmentEngine` that implements PLAN §3, and the Home tab that shows today's shipment. Serves "no unconscious consumption": a finite, sized list instead of a feed.

## Decisions
- D29 Tapping a card plays that video. (Start watching was removed, D59.)
- D30 No notifications, ever (no shipment pings, no badges).
- D31 (changed 2026-10-28) Top bar: "Inbox  42 min" and an ⓘ button that opens the info page with the countdown (D58).
- D32 Full-width YouTube-style cards.
- ⚙︎ Defaults: a shipment that comes due while the player is open is applied the next time Home appears, never mid-video; a video that fails to play (deleted/private/unembeddable) → SEEN + toast "That video isn't available anymore."

## ShipmentEngine (no UI, no network)
Inputs: followed creators (rank, mode), backlog, SEEN, current Home list + progress, settings, `now`, last shipment date. Outputs: the new Home list, the new backlog, new SEEN entries.
- `dueShipments(now)` → the shipment dates owed since the last one (multiple if days were skipped, ⚙︎a).
- `pick(budget, backlog, order)` → the greedy fill from PLAN §3.4 (fill until the full budget is reached, never past budget + 15, D48).
- `applyShipment` → Home = carryover + picked (D7), picked removed from backlog.
- `expire(now)` → backlog items published > 30 days ago → SEEN (D8).
- `canRefresh` / `refresh` → the PLAN §3.5 rules; returns `.notEnoughVideos` without using a refresh when the backlog is too thin.
- `markProgress`, `markWatched` (last 60 s, D11), `remove` (+ undo), `switchAway` (D12).
- Time is always injected (`now`), so tests can jump days and weeks instantly.

## Home behavior
- **Top bar:** "Inbox  42 min" + ⓘ (D31, D58). Total time = the remaining time of every video (time left in started ones).
- **Card:** full-width 16:9 thumbnail, duration badge, white progress bar if started, title (2 lines), creator · "2 days ago", ⋯ → Move up / Move down / "Remove video" → confirm (D64) → SEEN, Undo toast 5 s (D69).
- Tap card → player starting with that video (D29). Long-press + drag or ⋯ › Move up/down to reorder (D17), order persists.
- ~~Sticky **Start watching** at the bottom~~ removed (D59).
- Pull to refresh → PLAN §3.5 (confirmation alert, "Not enough new videos" path).
- **Empty A (all watched):** random ESV verse (never the same twice in a row), "Next shipment in 9h 12m".
- **Empty B (nothing found):** "No new videos from your creators." + **Find creators** → Following. Returning to Home after following → serve a shipment immediately. A creator followed from here brings their latest video even after day one; it is served by **Load my Inbox** (on the Inbox, which then reads "Almost ready", or on Following), and the Inbox shows "Getting today's videos…" while it is looked up (D218).
- **Onboarding (no creators):** "Welcome to KJ Tube" + one line on how shipments work + **Find creators**.
- Launch: Home renders from SwiftData immediately; due shipments and the backlog fetch run in the background and animate in.

## Acceptance criteria
Engine (unit tests):
- [x] E1 30-min budget, backlog of 12/10/9/25-min videos in rank order → picks 12+10+9 (31 min) and stops once the full budget is reached (D48).
- [x] E2 A video longer than budget + 15 is never picked.
- [x] E11 Rank wins (D99): the first video in order that would push the total past budget + 15 ends the pick; no lower-ranked video is picked to fill the gap. A video longer than budget + 15 on its own (E2) is passed over and does not end the pick.
- [x] E3 Ranked mode orders by creator rank, then newest; Random mode orders by newest only.
- [x] E4 Unwatched carryover stays on top and the new shipment is appended, no cap.
- [x] E5 3 skipped days → 3 shipments applied on the next open (each with its own weekday/weekend budget).
- [x] E6 Backlog items > 30 days old become SEEN.
- [x] E7 Refresh is refused when refreshes are used up, when > 60 s was watched since the last shipment, or (without spending a refresh) when the backlog can't reach budget − 15.
- [x] E8 After a refresh, all previous Home videos are SEEN.
- [x] E9 Reaching the last 60 s marks a video watched; exiting earlier keeps progress.
- [x] E10 Nothing in SEEN is ever picked again.

Home (Simulator):
- [ ] H1 With seeded data, Home shows cards, a correct header total and countdown, and the progress bar on a started video.
- [ ] H2 Reordering persists after relaunch.
- [x] H3 "Don't show this video" removes it; Undo restores it.
- [x] H4 Tap card → player opens on that video; Start watching → the top video.
- [x] H5 Pull to refresh shows the confirmation alert; confirming swaps the list and decrements the weekly count.
- [ ] H6 Empty A shows a verse and countdown; reopening the app shows a different verse.
- [x] H7 Empty B and onboarding show Find creators → the Following tab.
- [ ] H8 Cold launch to visible cards < 400 ms on device (Instruments).

## Verification (2026-10-27)
- 53 unit tests pass, including new store tests: first shipment on onboarding (D16), empty state A doesn't serve early, empty state B serves when a new creator brings videos (D26), new-upload fetch only adds uploads newer than the last seen, remove/undo persists, and old saved state still loads.
- Simulator, live YouTube (fresh install → follow Veritasium + 3Blue1Brown → Home):
  - H7 ✅ onboarding welcome + Find creators switches tabs.
  - First shipment ✅ appears immediately; header "35 min today · next in 15h 51m" was correct at 2:09 pm with 6 am shipments.
  - H5 ✅ pull to refresh → "You have 1 of 1 refreshes left" → Swap replaced the list.
  - H3 ✅ ⋯ → Don't show this video → empty state A with countdown → Undo restored it.
  - H4 ✅ Start watching opens the top video (placeholder until the Phase 4 player).
- Bug found and fixed: the Shorts check let a 1:13 Short through. On iOS, YouTube redirects every `/shorts/` request to m.youtube.com, so "200 = Short" never matched. It now follows redirects and checks whether the final page is still `/shorts/`.
- Not yet verified: H1's progress bar (needs the Phase 4 player to record playback), H2 reorder by hand (engine reorder is unit-tested), H6 verse (waits for the reviewed ESV list, D43), H8 launch timing (needs a real device).

## Out of scope
The player itself (Phase 4), Settings UI (Phase 6, defaults are used until then), widgets.

## Test plan
Engine fully unit-tested with a fake clock and fixture videos. Simulator: a debug launch argument seeds data and sets a fake "now" to walk H1–H7 without waiting.
