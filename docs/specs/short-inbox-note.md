# Short Inbox note
Status: draft (waiting for KJ's OK on the acceptance criteria)

## Summary
When the day's shipment can't fill the daily budget, a small friendly note sits at the bottom of the Inbox, under the last card. It says that's all for today and nudges KJ to follow more creators, with a "Find creators" button that opens the Following tab. Serves "trusted creators but still surprised": a thin Inbox is a sign to add creators, not to go looking elsewhere.

## Decisions (also in PLAN.md §2)
- D97 Short Inbox note: **When today's Inbox (new videos + carryover) has less than budget − 15 min right after the shipment**, the bottom of the Inbox shows "That's all for today. Your creators didn't post enough to fill your N minutes. Follow a few more to get more videos." with a **Find creators** button → Following tab.
- ⚙︎ Defaults (mine, flip any):
  - "Short" uses the same line as the rest of the app: less than budget − 15 min (PLAN §3.4, §3.5). So a 30-min day with 16+ min of videos shows no note.
  - It's measured once, right after the shipment (or a refresh). The next shipment decides again.
- **Hides once the first video of the day is finished** (KJ, 2026-11-01). Starting a video doesn't hide it; reaching the last 60 s (D11) does. It stays hidden until the next shipment.
  - Carryover counts: if yesterday's leftovers fill today, there's no note.

## Behavior
- Shown only when the Inbox has cards. An empty Inbox keeps its own screens (welcome, "No new videos from your creators", or the verse).
- Sits in its own section under the cards, in a rounded gray box: small search icon (magnifying glass), "That's all for today" headline, one line of gray text, and a blue "Find creators" button (D135).
- Not draggable; reordering cards is unchanged.
- Settings changes still wait for the next shipment (D44), so changing the budget doesn't change today's note.
- Saved state from older builds has no measurement yet, so no note until the next shipment.

## Acceptance criteria
- [ ] N1 — Given a 30-min weekday and only 10 min of new videos, when the shipment arrives, then the note shows under the last card.
- [ ] N2 — Given a shipment with 16 min or more on a 30-min day, then no note.
- [ ] N3 — Given 25 min of carryover and 5 min of new videos on a 30-min day, then no note.
- [ ] N4 — Given the note is showing, when KJ starts a video, then the note stays; when KJ finishes a video, then the note is gone until the next shipment.
- [ ] N5 — Given the Inbox is empty, then the note never shows (the empty screens do their job).
- [ ] N6 — Given a Saturday (60-min budget) with 40 min of videos, then the note shows and says "60 minutes".
- [ ] N7 — Given a short day, when the next shipment fills the budget, then the note is gone.
- [ ] N8 — Tapping "Find creators" switches to the Following tab.

## Out of scope
- Suggesting specific creators to follow.
- Showing the note anywhere but the bottom of the Inbox (no badge, no alert, no notification, D30).
- Changing how shipments are picked.

## Test plan
- Unit tests: `ShortInboxTests` covers N1–N7 and old saved state.
- Simulator: follow one creator with one short new video → shipment → scroll to the bottom → note shows → tap Find creators → Following tab opens (N8). Screenshot.
