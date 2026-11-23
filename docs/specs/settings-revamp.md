# Settings revamp
Status: approved

## Summary
Four changes to the Settings tab: refreshes are counted per day, limits can be loosened only once a week, Friday can count as weekend, and the stats box is rebuilt in the style of Apple's Screen Time. Serves "no unconscious consumption": the rules get simpler to read, and the stats show at a glance how the week is going.

## Decisions
- D144 **Refreshes per day: 0 / 1 / 2.** The count starts over with each day's shipment time. Swapping one video (D98) still uses 1. A saved "1 a week" becomes 1 a day; 2 or 3 a week becomes 2 a day. Default for new installs: 1.
- D145 **Limits loosen once a week.** Only loosening is held back (more minutes, more refreshes, moving the shipment time, turning Friday on). Tightening is always allowed. **Each limit has its own 7-day clock**, weekdays and weekends included. Replaces the 30-day raise lock.
- D146 **"Friday is weekend" switch**, off by default. When on, Friday's shipment uses the weekend minutes. It is a limit, so it follows D145. If weekends don't have more minutes than weekdays, the switch gives nothing extra and isn't held back.
- D147 **Stats, Screen Time style**, daily minutes only. No per-creator stats.

## Behavior

**Limits box**
- Weekdays [30 · 60 · 90 min], Weekends [30 · 60 · 90 min], Friday is weekend [switch], Shipment arrives [hour], Refreshes per day [0 · 1 · 2].
- Loosening asks first: "Raise to 60 min? You can't raise this again until Nov 18." After confirming, that limit is locked for 7 days. While locked, a tap shows "Not yet. You can change this again on Nov 18."
- Footer: "Changes start with the next shipment." plus a line for each active lock.
- A lock saved by the old rules (up to 30 days) is cut down to 7 days from when it was set, so nobody waits longer than the new rule.

**Refreshes**
- Pull to refresh and "Swap this video" check refreshes left today. The alert reads "Uses 1 of N refreshes today."
- The Inbox ⓘ page shows refreshes left today.

**Stats (Screen Time style)**
- On the Inbox ⓘ page under "How it works", in their own box with no title (D149). Not in Settings.
- Top: "Daily Average" label, a big number ("42m"), and a small line next to it: "↓ 12% from last week" (hidden when last week is empty). The average counts the days so far this week.
- A bar chart for one week, Monday to Sunday (the app's week). One bar per day, a dashed line for the daily average. Bars over that day's budget are orange.
- Arrows above the chart step back and forward a week, as far back as the oldest saved day (data is trimmed at 60 days).
- Touch a bar to see that day: "Tuesday, Nov 10 · 34m of 60m".

## Acceptance criteria
- [ ] V1 With 1 refresh a day, a refresh used today is back after the next shipment time; with 0, pull to refresh says none left.
- [ ] V2 Swapping one video uses 1 of today's refreshes.
- [ ] V3 An old "3 a week" setting shows as 2 a day after the update; "1 a week" shows as 1 a day.
- [ ] V4 Raising a limit asks first, then locks that limit for 7 days with the date shown. Lowering always works, even while locked. Lowering weekday or weekend minutes asks "Are you sure?" first and warns that going back up uses the once-a-week raise (D210).
- [ ] V5 A lock from the old 30-day rule ends no later than 7 days after it was set.
- [ ] V6 With "Friday is weekend" on, a Friday shipment uses the weekend minutes; off, it uses weekday minutes. Stats use the same rule for each day's budget line.
- [ ] V7 Stats show the daily average for the shown week, the change from the week before, (the total and days-within-budget are worked out but no longer shown, D149).
- [ ] V8 The week arrows move between weeks and stop at the current week and at the oldest week with data.
- [ ] V9 All new settings and locks are still there after closing and reopening the app.

## Out of scope
Skip Ad switch and Creator order (untouched). Screen Time blocking. Exporting stats. Changing what counts as a watched minute.

## Test plan
Unit: daily refresh window at shipment time, migration of the weekly value, 7-day lock rules and old-lock trimming, Friday budget, week stats (average, change, days within budget). Phone or Simulator: walk V1 to V9 in Settings and the Inbox.
