# Fill a short day after finding creators
Status: approved (KJ, 2026-11-11). Backfill videos are starters (D80), so fresh uploads always go first on later days.

## Summary
When today's shipment didn't fill the budget, the Inbox shows "That's all for today" with a Find creators button (D97). Today, following someone there does nothing until tomorrow. With this feature, KJ can follow new creators and reorder them on the Following tab, and on coming back to the Inbox the app fills the leftover time for today, walking creators in Following order. Serves "trusted creators but still surprised": a thin day is fixed by adding trusted creators, not by going to YouTube.

## Decisions (also in PLAN.md §2)
- D136 Fill a short day: on a short day, coming back to the Inbox from Following tops up today's Inbox to the budget. Nothing is pulled while KJ is still on Following.
- KJ's answers (2026-11-11):
  - **Whose videos:** creators followed that day bring their **latest long-form video**, one each (a change to D92 for short days only). Older videos from creators KJ already followed are not pulled.
  - **When it works:** only while the "That's all for today" note is showing, so before the first video of the day is finished. After that, the day is done (no way around the daily limit).
  - **How old:** the latest video counts if it was posted in the last 30 days (same as the waiting list rule, D8).
- ⚙︎ Default (mine, flip it): the fill uses the normal picker on everything waiting, so in the rare case where a video was left waiting because a longer one above it ended the pick (D99), a reorder alone can bring it in. Most short days have nothing waiting, so reorder alone does nothing.

## Behavior
- A day is "short" by the D97 rule: Inbox total under budget − 15 min at the shipment.
- On Following during a short day, each new follow fetches that creator's latest eligible video (no Shorts, live, replays, or anything over budget + 15) and keeps it waiting. The Inbox is not touched yet.
- On switching to the Inbox tab: the picker (§3.4) runs on the waiting videos in Following order, with the time already in the Inbox counted first. Picked videos are added under the cards already there. Rank still wins (D99): the first video that would go past budget + 15 min ends the pick.
- Leftover time = budget minus the length of today's videos as measured at the shipment (plus any earlier fill). Removing a video doesn't make more room.
- If the Inbox is no longer short after the fill, the note goes away. If it is still short, the note stays.
- A fetched video that didn't fit stays waiting as a starter (D80): one more shipment, then it leaves.
- No refresh is used. No alert. New cards just appear.
- Offline or YouTube error on a follow: nothing is added for that creator; the usual retry runs on the next visit (existing behavior).
- Unfollowing a creator before going back removes their waiting video.
- A normal day (not short) is unchanged: follows bring only future uploads (D92), reorder waits for the next shipment (D44).

## Acceptance criteria
- [ ] F1 — Given a 30-min day with 10 min in the Inbox, when KJ follows a creator whose latest video is 15 min and goes back to the Inbox, then that video is added at the bottom.
- [ ] F2 — Given F1, while KJ is still on Following, then the Inbox list is unchanged.
- [ ] F3 — Given a short day and two new follows A (rank above) and B, each with a 15-min latest video and 20 min left, when KJ goes back, then A's video is added first, and B's only if it fits under budget + 15.
- [ ] F4 — Given the same two follows, when KJ drags B above A before going back, then B's video is picked first.
- [ ] F5 — Given the fill brings the Inbox to budget − 15 min or more, then the "That's all for today" note is gone.
- [ ] F6 — Given the fill still leaves the day short, then the note stays.
- [ ] F7 — Given a day that is not short, when KJ follows a creator, then nothing is added today (D92 as before).
- [ ] F8 — Given a short day where KJ has finished a video, when KJ follows a creator and goes back, then nothing is added today.
- [ ] F9 — Given a new follow whose latest video is a Short, live, or longer than budget + 15, then it is skipped (their next eligible latest video is used, same as day one).
- [ ] F10 — Given a new follow whose latest video is older than 30 days, then nothing is added.
- [ ] F11 — Given a fill, then the refresh count is unchanged and no video already in the Inbox moved or left.
- [ ] F12 — Given a video KJ has already seen (SEEN), then it is never added.

## Out of scope
- Suggesting creators.
- Filling on days that weren't short, or after the first video is finished.
- Pulling several old videos from one creator.
- Any change to the daily shipment, refresh, or swap.

## Test plan
- Unit tests: `FillShortDayTests` in `KJTubeTests` covers F1–F12 on `ShipmentEngine` (new `fillToday` step) and `AppStore.follow`.
- Simulator: one creator with one short video → shipment → note shows → Find creators → follow two creators → reorder → Inbox tab → new cards in order, note gone.
