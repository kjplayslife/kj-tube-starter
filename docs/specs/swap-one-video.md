# Swap one video
Status: approved (KJ, 2026-11-02)

## Summary
Trade one Inbox video for a new one from the ⋯ menu, without swapping the whole day. It uses one of the week's refreshes, so it stays a rare do-over, not a way to browse.

## Decisions (also in PLAN.md §2)
- D98 Swap one video: **⋯ › "Swap this video"** on an Inbox card. **Uses 1 refresh** (same weekly count as pull to refresh).
- ⚙︎ Defaults (mine, flip any):
  - Works **any time**, even after you started watching (pull to refresh stops after 60 s; this one doesn't, since it's just one video).
  - The new video is the **next one in line** (same order as shipments) that is **no more than 15 min longer** than the one it replaces, so the day stays about the same length.
  - The new video takes the **same spot** in the list. The old one is gone for good (SEEN), like a refresh.
  - Only on Inbox cards, not in the player's list.

## Behavior
| Situation | What happens |
|---|---|
| Allowed | Alert: "Swap this video?" / "Uses 1 refresh. You have 1 of 1 left this week. This video won't come back." [Swap] [Cancel] → the new video slides into the same spot |
| No refreshes left | Alert: "No refreshes left this week" / "More on Monday." [OK] |
| Nothing fits | Alert: "No new video to swap in" / "Follow more creators to get more videos." [Find creators] [OK]. No refresh used |

The Inbox ⓘ page gets a tip: "⋮ › Swap this video trades one video for a new one. Uses 1 refresh, any time."

## Acceptance criteria
- [ ] S1 Swap puts a new video in the same spot, the old one never comes back, and 1 refresh is used.
- [ ] S2 A video more than 15 min longer than the old one is skipped.
- [ ] S3 Swapping works after watching has started.
- [ ] S4 With no refreshes left, it's refused and nothing changes.
- [ ] S5 When nothing fits, it's refused and no refresh is used.
- [ ] S6 Swaps and pull to refresh share one weekly count, which resets Monday at shipment time.

## Out of scope
Picking the replacement yourself, swapping from the player.

## Test plan
Unit: `SwapVideoTests` (S1–S6). Simulator: ⋯ menu shows "Swap this video", each alert, new card animates into place.
