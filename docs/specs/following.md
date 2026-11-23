# Following (Phase 2)
Status: approved

## Summary
The Following tab is where KJ chooses which creators shipments come from, and in what priority. Serves "trusted creators only." Following a creator seeds the backlog with their last 3 eligible uploads.

## Decisions
- D25 Tapping a followed creator does nothing. Rows are only for reordering and unfollowing (no browsing).
- D26 Following mid-day: the new creator's 3 uploads go to the backlog for the next shipment. Exception: when Home is in empty state B/onboarding, returning to Home serves a shipment right away (PLAN §4).
- D27 Add via search **and** pasting a channel URL, video URL or @handle. Share-sheet extension: not in v1.
- D28 First launch opens Home with a welcome + "Find creators" button.
- ⚙︎ Defaults: up to 10 search results; when looking for the "last 3 eligible" uploads, scan up to the last 50; full swipe unfollows with no confirmation (Undo toast, 5 s); no limit on the number of creators.

## Behavior
**Layout (top to bottom):** search field → followed list (Ranked / Random moved to Settings, D74) (or search results while searching).

**Search**
- Runs on submit (Return), not per keystroke. Results: avatar, name, @handle, subscriber count, **Follow** button (shows **Following ✓**, disabled, if already followed).
- Paste detection: `youtube.com/@handle`, `youtube.com/channel/UC…`, `youtube.com/watch?v=…` / `youtu.be/…` (→ that video's channel), or `@handle` → resolves straight to a single result.
- Cancel / clear → back to the followed list.

**Following a creator**
- Saves the creator at the bottom of the rank (⚙︎f).
- In the background: fetch their uploads playlist, check eligibility (PLAN §3.2), and add their newest eligible (long-form) video to the backlog (D79; was 3). It is a starter: new uploads go first, it gets one shipment, and a newer upload from that creator replaces it (D80). After day one (once anything has been served), no old video is added: only uploads posted after the follow (D92). The row shows a small spinner until done.
- If none of their last 50 uploads are eligible, the row shows "No eligible videos yet".

**Followed list**
- Row: avatar, name, "Last upload 3d ago" (newest long-form video only, D230). Tap: nothing.
- Long-press + drag to reorder = rank (top = served first). The rank number is shown faintly on the left when Ranked is selected; hidden in Random.
- Swipe right → **In Order** and **Any Length** buttons on the left; a tap flips that switch, and a ✓ shows when it is on (D172). Tapping the icons shows a short reminder of what they mean (D174). The first time a switch is ever turned on, a short note explains it first; Continue turns it on and it never asks again (D173). A creator with a switch on shows a small icon beside the name. The row's corners round while it is swiped, held or dragged (D172).
- Swipe left → Unfollow (full swipe works). Removes their backlog videos (⚙︎d); videos already on Home stay. Undo toast for 5 s.
- Empty: "Follow creators you trust. Their new videos become your daily shipment."

**Ranked / Random** (in Settings, default Ranked): saved immediately; affects the next shipment only.

**Errors:** offline or API error → inline message under the search field with **Retry**. Quota exceeded → "YouTube search is resting until tomorrow." Followed list still works from local data.

## Acceptance criteria
- [x] AC1 Searching "Veritasium" + Return shows ≤ 10 channel results with avatar, name and subscriber count.
- [x] AC2 Pasting `https://www.youtube.com/@veritasium`, a `watch?v=` URL, or `@veritasium` shows exactly that channel.
- [x] AC3 Tapping Follow adds the creator at the bottom of the list. Within a few seconds, 3 eligible videos (no Shorts/live/replays/members-only) are in the backlog (unit-tested with fixtures).
- [x] AC4 An already-followed channel shows "Following ✓" in results and can't be added twice.
- [x] AC5 Long-press + drag reorders creators; the order persists after relaunch.
- [x] AC6 Swiping to unfollow removes the creator and their backlog videos; Undo within 5 s restores both.
- [x] AC7 The Ranked/Random choice persists after relaunch.
- [x] AC8 Tapping a followed row does nothing.
- [x] AC9 In airplane mode, search shows the offline message + Retry, and the followed list still shows.
- [x] AC10 Following mid-day (Home has videos) doesn't change today's Home list.

## Verification (2026-10-27)
- Unit tests: link parser (13 inputs), ISO durations, API decoding, eligibility + "last 3 eligible", and store tests for AC3–AC7, AC9, AC10 (fake YouTube, in-memory SwiftData).
- Simulator against live YouTube: AC1 (search "Veritasium" → 10 results with avatars + subscriber counts), AC2 (typed `youtube.com/@3blue1brown` → exactly that channel), AC3 (follow → "Last upload 2 days ago", videos in backlog), AC4 ("Following ✓"), AC6 (swipe → toast → Undo restores, confirmed via log).
- Changed while testing: the Undo toast sits at the top (under the search bar), and links typed character by character are debounced (400 ms) so only the latest lookup shows.
- AC5 drag-reorder and AC9 airplane mode were covered by unit tests only, not by hand in the Simulator.

## Out of scope
Share extension, creator detail pages, per-creator settings, importing YouTube subscriptions.

## Test plan
- Unit: URL/handle parser (table of inputs), eligibility filter, "last 3 eligible" selection, unfollow + undo, rank persistence. YouTube responses come from JSON fixtures; no live network in tests.
- Simulator: walk AC1–AC10 with screenshots.
