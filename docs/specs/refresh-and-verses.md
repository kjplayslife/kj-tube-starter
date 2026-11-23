# Refresh, verses & countdown (Phase 5)
Status: approved

## Summary
The finishing pieces of Home: pull-to-refresh (one honest do-over per week), the Bible verse shown when the day's shipment is done, and the live countdown to the next shipment. The rules live in PLAN §3.5 and the `ShipmentEngine` (Phase 3). This spec covers the UI and the verse system.

## Decisions
- D40 Verse themes: **Rest & Sabbath, Good work, Stillness & attention, Contentment** (~13 each).
- D41 Rotation: **shuffle bag**, every verse once in random order before any repeat. A new verse on every app open (a cold launch or returning from the background after > 5 min) while Home is empty.
- D42 "Refreshes left" appears **only in the confirmation alert**.
- D43 Claude drafts [verses.md](verses.md); **KJ checks each against esv.org** before it ships.
- ⚙︎ Defaults: the verse shows its reference under the text (no theme label); the countdown ticks every minute (every second under 1 min); the week for refresh counting starts Monday at shipment time.

## Behavior

**Pull to refresh** (Home, only when the list isn't empty)
| Situation | What happens |
|---|---|
| Allowed | Alert: "Swap today's videos?" / "You have 1 of 1 refreshes left this week. These videos won't come back." [Swap] [Cancel] → spinner → new list animates in |
| No refreshes left | Alert: "No refreshes left this week. More on Monday." [OK] |
| Watched > 60 s since the shipment | Alert: "You've already started today's shipment, so it can't be swapped." [OK] |
| Backlog too thin | Alert: "Not enough new videos to swap in. Follow more creators to get more." [Find creators] [OK]. No refresh used |
| Offline | Refresh still works (it uses the local backlog) |

**Verse (Home empty state A)**
- Centered, serif type, the verse text, then "— Psalm 46:10 (ESV)" below it, and "Next shipment in 9h 12m" at the bottom.
- The verse list is bundled as `verses.json` (generated from `docs/specs/verses.md`), so it works offline.
- Shuffle-bag position is persisted so restarts don't reset it.

**Countdown**
- Header (D31): "42 min today · next in 9h 12m". Empty state: "Next shipment in 9h 12m".
- When the countdown reaches 0 while Home is visible, the shipment is applied on the spot and the list animates in.

## Acceptance criteria
- [x] R1 Pull to refresh when allowed shows the alert with the correct count; Swap replaces the list and the count drops by 1.
- [x] R2 Each of the 3 refusal cases shows its own alert and uses no refresh.
- [x] R3 The weekly count resets Monday at shipment time (fake clock).
- [x] R4 Empty Home shows a verse with its reference; relaunching shows a different one; after N launches all N verses have appeared exactly once (unit test).
- [ ] R5 The countdown is correct across midnight and the weekday→weekend change.
- [ ] R6 With Home open as the countdown hits 0, the new shipment appears without relaunching.
- [ ] R7 Verses render with the largest Dynamic Type without truncation.

## Verification (2026-10-27)
- Unit tests: shuffle bag (all verses once before a repeat, never twice in a row across a reshuffle, 20 seeds), bundled list loads with 4 themes, a new verse on cold launch and after 5+ min away but not after a quick switch, plus the Phase 3 refresh tests (R2/R3).
- Simulator: removing the last video shows the verse in serif with "— Matthew 6:34 (ESV)" and "Next shipment in 15h 19m"; the refresh alert was checked in Phase 3 (R1).
- `scripts/build_verses.py` regenerates `KJTube/KJTube/Resources/verses.json` from `verses.md`, so re-run it after editing the list.
- ⚠️ The 52 verses are still Claude's unreviewed draft (D43); check them before TestFlight.
- Not yet verified: R5 across midnight by hand, R6 by hand (the minute tick applies due shipments; unit-tested in the engine), R7 largest Dynamic Type. The countdown updates every minute, not every second in the last minute.

## Out of scope
Favoriting or sharing verses, picking a translation in-app, notifications.

## Test plan
Unit: shuffle bag, refresh gating, week boundary. Simulator: R1, R2, R4, R6, R7 with seeded data + fake clock.
