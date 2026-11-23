# Play Next in full screen
Status: approved

## Summary
In full screen, near the end of a video, a blue **Play Next** button pops up in the corner, the same blue glass button that sits under the video in portrait. One tap moves on without leaving full screen. Serves "no unconscious consumption": moving on is still a choice (no autoplay), it's just easy to make.

## Decisions (also in PLAN.md §2)
- D102 Play Next in full screen: shows in the **last 15 s** only, however long the video is (D161; was the last 60 s, or the last 10 % under 10 min).
- ⚙︎ Defaults (mine, flip any):
  - Sits in the **bottom-right corner**, over the video, above the seek bar when the controls are showing.
  - Shows **even when the controls are hidden** (that's the point); fades in.
  - ~~Same look and words as the portrait one: blue glass, "Play Next" with ▸▸.~~ Changed by D219: the same dark pill as Skip Ad, in the same spot and size, reading "Next video" with ▸▸. With the controls showing it sits 8 pt above the mute and full screen buttons.
  - Tapping it acts like the portrait button. In that window the video already counts as watched (D38), so there's **no "Play next video?" alert**; the next video just starts, still in full screen.
  - **Last video of the day: no button** (nothing is next). The end-of-video "Next video" / "That's today's shipment" screens are unchanged.
  - Portrait is unchanged. **Leaving full screen hides it** (KJ, 2026-11-09); the portrait button under the video is still there.
  - Seeking back out of the window hides it again.

## Acceptance criteria
- [x] F1 — Given a 20-min video in full screen with another video next, when 15 s are left, then the blue Play Next button shows bottom-right; at 16 s left it doesn't (D161).
- [x] F2 — Given a 2-min video, then the button shows at 15 s left, not before (D161).
- [x] F3 — Given the controls are hidden, then the button still shows; given they're showing, it doesn't cover the seek bar or the full-screen button.
- [x] F4 — Tapping it starts the next video with no alert and stays in full screen.
- [x] F5 — Given it's the last video of the day, then no button.
- [x] F6 — Seeking back before the window hides the button.
- [x] F7 — Given the button is showing, when KJ leaves full screen, then it disappears.

## Out of scope
Autoplay, a countdown, showing the next video's title or thumbnail, changing the portrait button.

## Test plan
- Unit (`PlayerControllerTests`, fake player): window math for long and short videos (F1, F2), no button on the last video (F5), hides after seeking back (F6), tapping goes straight to the next video (F4).
- Simulator: full screen near the end of a video with controls hidden and showing, screenshots (F1, F3, F4).

## Verification (2026-11-09)
- 171 unit tests pass, including the new full-screen Play Next tests (F1, F2, F4, F5, F6).
- Simulator (iPhone 17, a 19:38 video with another next): no button at 79 s left; at 37 s left the blue Play Next shows bottom-right with controls hidden (F1); with controls showing it sits above the seek bar, nothing covered (F3); rotating back to portrait hides it and the portrait Play Next is still there (F7); tapping it starts the next video at once, still in full screen, no alert (F4).
- Note: with controls hidden, the button's right end sits ~25 pt past the video's edge, in the black side bar (the iPhone 17 screen is wider than 16:9).
- D219, Simulator (iPhone 17, an 18:40 video with another next, full screen, paused in the last 15 s with the controls showing): the dark "Next video" pill shows bottom-right, above the mute and full screen buttons with a gap, nothing covered.
