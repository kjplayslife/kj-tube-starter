# Settings (Phase 6)
Status: approved (limits and stats changed by [settings-revamp](settings-revamp.md), D144–D147)

## Summary
The Settings tab: daily budgets, shipment time, refreshes per week, and watch stats, each with deliberate friction on loosening limits (PLAN §3.6). Serves "no unconscious consumption": tightening is instant, loosening is rare.

## Decisions
- D44 Changes take effect at the **next shipment**. Today's list is never touched by Settings.
- D45 Shipment time in **whole hours**.
- D46 Stats: **minutes watched per day, last 14 days**.
- D47 **No "reset all data"** option. Starting over means deleting the app.
- ⚙︎ Defaults: weekday + weekend budgets share one 30-day increase clock; refreshes have their own 30-day increase clock; developer tools (fake clock, seed data) exist **only in Debug builds**, never in TestFlight (they'd be a loophole); the Settings footer shows the version + build number.

## Behavior

**Sections** (D67)
1. **Limits**: Weekdays [30 · 60 · 90 min], Weekends [30 · 60 · 90 min] (segmented), Shipment arrives [6:00 am ▾], Refreshes a week [0 · 1 · 2 · 3]. One footer: "Changes start with the next shipment." plus a "Can … again on Nov 26." note for each active lock.
2. **Stats**: one bar chart (below).
3. Footer: "KJ Tube 1.0 (42)".

**Friction rules (PLAN §3.6)**
- Decrease budget/refreshes → applied at once (for the next shipment), no confirmation.
- Increase budget/refreshes → confirmation: "Raise your weekday budget to 60 min? You won't be able to raise budgets again until Nov 26." [Raise] [Cancel].
- While locked, higher options are disabled, with a footnote: "Can raise again on Nov 26."
- Shipment time change → confirmation: "Move shipments to 7:00 am? You can change this again on Nov 3." While locked, the picker is disabled with that date.
- Every change shows a footnote "Starts with the next shipment" (D44).

**Stats**
- One bar chart of the last 14 days, oldest on the left. A dashed line shows each day's budget. Touching a bar shows that day: "Tuesday, Oct 27 · 34 min of 60 min".
- Minutes = seconds of video content played (same measure as the refresh rule), excluding ads.
- A small line at the top: "This week: 2h 41m of 3h 30m".

## Acceptance criteria
- [x] S1 Lowering a budget applies to the next shipment and today's list is unchanged.
- [x] S2 Raising a budget asks for confirmation; afterwards, raising weekday or weekend is disabled for 30 days with the unlock date shown, while lowering stays enabled.
- [x] S3 Refreshes follow the same rule on their own 30-day clock.
- [x] S4 Changing the shipment time asks for confirmation and locks the picker for 7 days; the next shipment uses the new hour.
- [x] S5 Stats show the last 14 days correctly, including days with no watching (fake clock + seeded watch log).
- [x] S6 All settings and lock dates persist across relaunch.
- [ ] S7 Release builds contain no developer tools (verified by building Release and checking there's no debug menu).

## Verification (2026-10-27)
- Unit tests: lower anytime, raise → confirm + 30-day lock, refused while locked, shipment-time 7-day lock, shared budget clock, moving the time later never gives a second shipment that day, the watch log per day and Mon–Sun week totals, 60-day trim, and everything persisting across relaunch.
- Simulator: defaults show correctly; raising weekdays to 60 shows "Raise to 60 min? … until Nov 26"; after confirming, the footer reads "Can raise budgets again on Nov 26" and raising weekends says "Not yet"; the weekly budget updates to 7 h.
- Debug-only tools (`-resetData`, `-seedCreators`, `-undoSeconds`, `seedHome`) are inside `#if DEBUG` and not in Release builds (S7 by construction; not yet checked with a Release build).
- Not yet verified by hand: the shipment-time picker, refreshes, and stats with real watch data.

## Out of scope
Screen Time blocking (Phase 8 adds its own section), theme options, exporting data.

## Test plan
Unit: lock/unlock logic for each setting at boundary dates, stats aggregation. Simulator: S1–S6 with the fake clock. S7: a Release-configuration build check.
