# Any length
Status: approved (KJ, 2026-11-12)

## Summary
Some creators only post very long videos (an hour or more). Today a video longer than the day's time + 15 min is never served (D9), so on a 30-min weekday those creators never show up. An **"Any Length"** switch on a followed creator lets their videos through no matter how long. A video that goes over the day's time is the **only new video that day**. It serves "trusted creators": KJ picks, one creator at a time, who is worth going over for.

## Decisions (also in PLAN.md §2)
- D151 Any length: a **per-creator switch**, off by default. On: that creator's videos are never "too long" (changes D9 for them only).
- An over-time video comes **only when it is first in line** that day, and then it is the **only new video** of that shipment.
- If a higher-ranked creator's video is picked first, **the long video waits** (KJ, 2026-11-12: "Long video waits"). It comes on the next day it is first in line, and still expires after 30 days (D8).
- **No limit** on turning it on (KJ, 2026-11-12): any creator, any time. No 7-day clock.
- Live streams, premieres and stream replays **stay blocked** (D13). That check never looks at length, so the switch can't let them in.
- The switch is saved with the engine's state (a set of creator IDs), like Watch in Order. No database change.
- ⚙︎ Defaults (mine, flip any):
  - The switch lives in the **hold menu** on Following: "Any Length" with an hourglass-plus icon, a checkmark when on. Swipe left stays just Unfollow.
  - The row shows **"Any length"** on its small gray line (after "In order" when both are on).
  - While a long video waits behind a higher creator's video, it is **passed over**, so lower creators can still fill the day (same as a too-long video today). It does not end the pick.
  - Videos left over in the Inbox from earlier days **don't block it** (carryover never counts, D7).
  - It takes effect at the **next shipment or refresh**. The Inbox never changes when the switch is flipped.
  - "Swap this video" and the short-day fill **never bring an over-time video** (a swap stays within 15 min of the old video; a fill only adds to a day that already has videos).
  - **Undo** after an unfollow brings the switch back. Following the creator again later starts with it off.

## Behavior
"Over time" means longer than the day's time + 15 min (30-min day: over 45 min).

| Situation | What happens |
|---|---|
| Hold a creator on Following | The menu has "Any Length" under "Watch in Order". Tap to turn on or off (light haptic). The row shows "Any length" while on |
| Switch on, their 75-min video is first in line, 30-min day | The Inbox gets that one video. Nothing else is added that day |
| Switch on, a higher creator's 20-min video is first | The 20-min video comes, the day fills up as normal from other creators, and the 75-min video waits |
| Switch on, their video is 25 min | Normal rules. Nothing changes |
| Switch off (default) | Same as today: an over-time video is never served |
| Refresh (pull down) | Uses the same pick, so an over-time video that is first in line can come as the only video |
| Random mode | "First in line" means the newest waiting video overall |
| A live stream or stream replay from that creator | Never shown, as today |

Rule for the picker (PLAN §3.4):
```
for video in ordered backlog:
    if video is over time:
        if creator has Any Length and nothing is picked yet (and no time already counted):
            picked = [video]; stop
        else: continue            # passed over; waits (Any Length) or is never served (D9)
    ... the rest as today
```

## Acceptance criteria
- [ ] L1 With the switch on, an over-time video that is first in line is served, and it is the only video in that shipment.
- [ ] L2 With the switch off, an over-time video is never served (as today).
- [ ] L3 With the switch on, when a higher-ranked video is picked first, the over-time video is not served that day, the rest of the day fills as normal, and the long video comes on a later day when it is first in line.
- [ ] L4 A video from an Any Length creator that fits the normal limit follows the normal rules.
- [ ] L5 Refresh can bring an over-time video as the only video; swap and the short-day fill never do.
- [ ] L6 Turning the switch on or off never changes the Inbox.
- [ ] L7 The switch is saved across relaunches; state from an older build opens with every creator off; Undo after an unfollow brings it back.
- [ ] L8 Following: hold a creator → "Any Length" shows, with a checkmark when on, and the row shows "Any length". Works together with Watch in Order.
- [ ] L9 Live streams, premieres and stream replays from an Any Length creator are still left out.

## Out of scope
A cap on length. A limit on how many creators or how often it can be turned on. Splitting a long video over several days. Letting a long video push out a higher creator's video. A swipe button for it.

## Test plan
Unit: `AnyLengthTests` (L1–L6) on `ShipmentEngine`; store tests for L7; L9 is covered by the existing eligibility tests (the switch does not touch `UploadsLoader`). Simulator: hold a creator, turn it on, see the checkmark and tag; relaunch and see it kept.
