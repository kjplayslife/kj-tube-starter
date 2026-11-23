# Watch in order
Status: approved (KJ, 2026-11-12)

## Summary
Some creators post a series, where each episode follows the last. Today the Inbox takes a creator's **newest** waiting video first, so when two or three episodes are waiting, the latest one arrives first and the earlier ones come later, out of order. A **"Watch in Order"** switch on a followed creator makes their waiting videos arrive **oldest first**. Everyone else stays newest first. It adds no watch time, so it keeps "no unconscious consumption" intact.

## Decisions (also in PLAN.md §2)
- D150 Watch in order: a **per-creator switch**, off by default. On: that creator's waiting videos are served **oldest first**. (KJ picked this over "oldest first for everyone" and "guess from titles", 2026-11-12.)
- The switch is saved with the engine's state (a set of creator IDs), not on the SwiftData `Creator`, so there is no database change.
- ⚙︎ Defaults (mine, flip any):
  - The switch lives in the **hold menu** of a creator on Following: "Watch in Order", with a checkmark when on. It works in Ranked and Random.
  - A creator with it on shows **"In order"** at the end of their small gray line ("Last upload 2 days ago · In order").
  - **Only the order inside that creator changes.** Their rank against other creators, the time budget, and "rank always wins" (D99) are untouched.
  - It takes effect at the **next shipment, refresh, swap or short-day fill**. Videos **already in the Inbox never move** (drag them if needed).
  - Waiting videos still **expire after 30 days** (D8), and a video longer than budget + 15 min is still never served (D9), so a very old or very long episode can still be missed.
  - **Undo** after an unfollow brings the switch back as it was. Following the creator again later starts with it off.

## Behavior
| Situation | What happens |
|---|---|
| Hold a creator on Following | The menu has "Watch in Order" above Unfollow. Tap it to turn it on or off (light haptic). The row shows "In order" while on |
| Switch on, 3 episodes waiting, room for 1 today | Today brings episode 1. Episodes 2 and 3 wait and come on later days, in order |
| Switch on, room for all 3 | They arrive in the Inbox as 1, 2, 3 from top to bottom |
| Switch off (default) | Same as today: newest first |
| Ranked mode | The creator keeps their place in the rank. Only their own videos flip to oldest first |
| Random mode | The Inbox is still newest first across creators. An in-order creator's videos keep the same spots in line, but oldest fills the earliest spot |
| Newest episode is already in the Inbox when the switch is turned on | It stays where it is. The older ones arrive under it later, in order |

Rule for the picker (PLAN §3.4): sort the waiting videos as today. Then, for each in-order creator, put their videos back into the same spots, oldest first.

## Acceptance criteria
- [ ] W1 With the switch on and several of a creator's videos waiting, a shipment serves the oldest first, and the rest follow oldest first on later shipments.
- [ ] W2 With the switch off, the order is exactly as before (newest first).
- [ ] W3 In Ranked mode, an in-order creator's videos keep their place against other creators. Rank still wins, and the budget rules (D48, D99, D9) are unchanged.
- [ ] W4 In Random mode, an in-order creator's videos take the same spots in line, oldest first. Other creators' videos don't move.
- [ ] W5 Refresh, "Swap this video" and the short-day fill use the same order.
- [ ] W6 Turning the switch on or off never moves or removes videos already in the Inbox.
- [ ] W7 The switch is saved and still set after the app is closed and reopened. An app updated from an older build opens fine with every creator off.
- [ ] W8 Undo after unfollowing an in-order creator brings them back with the switch on.
- [ ] W9 Following: hold a creator → "Watch in Order" shows, with a checkmark when on, and the row shows "In order".

## Out of scope
Guessing series from titles. Picking single playlists or series inside a creator. Holding back a newer episode until the older one is watched. Keeping episodes longer than 30 days. Re-sorting videos already in the Inbox.

## Test plan
Unit: `WatchInOrderTests` (W1–W6) on `ShipmentEngine`; store tests for W7–W8 if the store has a test harness, else covered in the Simulator. Simulator: hold a creator, turn it on, see the checkmark and "In order"; relaunch and see it kept.
