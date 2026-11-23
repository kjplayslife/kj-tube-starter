# One-time reset: only the last 24 hours (D91)

## Summary
KJ's install pulled several old videos per creator on day one, before D79/D80. Those still sit in the Inbox and waiting list. Clear them once, so the app acts like day two.

## Behavior
- Runs once, the next time the app opens (on the first shipment check).
- Every video on Home or in the backlog published more than 24 hours ago goes to SEEN (never shown again). In-progress videos too.
- Videos from the last 24 hours stay. New uploads fetched on that open count too.
- Follows, rank, settings, refresh count and stats don't change.
- If Home ends up empty, fresh uploads are served right away; if there are none yet, Home shows the "nothing new" state until some arrive.
- A brand-new install (no shipment yet) skips it.

## Acceptance criteria
1. After update, Inbox shows no video older than 24 hours.
2. Followed creators are all still there.
3. A video posted in the last 24 hours by a followed creator shows up.
4. Cleared videos never come back.
5. It only happens once.

## Test plan
- Unit: `RecentResetTests` (engine), `HomeStoreTests.oneTimeRecentReset` (store, runs once).
