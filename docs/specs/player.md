# Player (Phase 4)
Status: approved

## Summary
A YouTube-mobile-style player for today's shipment, minus comments, likes, recommendations and descriptions. Uses the official YouTube IFrame player (D3) behind the `VideoPlayer` protocol, with our own SwiftUI controls on top. Serves "no unconscious consumption": no autoplay, no rabbit holes, and once you deliberately leave a video it's gone.

## Decisions
- D33 Playback speed **1x–2x** (1, 1.25, 1.5, 2), remembered across videos.
- D34 Fullscreen by **rotating to landscape or tapping the button**.
- D35 (changed 2026-10-28) **Description shown**, collapsed to 2 lines with "more" and "less"; links are blue and open in Safari. Creator avatar + subscriber count shown.
- D36 App backgrounded / phone locked → **pause**, progress saved.
- D37 Last video ends → **auto-return to Home** after 3 s (Home then shows verse + countdown).
- D38 Seeking into the last 60 s **counts as watched** (same as finishing).
- D39 **CC toggle**, remembered across videos.
- ⚙︎ Defaults: no mini-player (swiping down/back fully leaves the player); the screen stays awake while playing; the home indicator auto-hides in fullscreen; ads are shown as YouTube serves them (D4) and ad time is never counted as watched; "watched seconds" for the refresh rule (PLAN §3.5) = seconds of video content played, regardless of speed.

## Architecture
- `protocol VideoPlayer`: `load(id, startAt)`, `play`, `pause`, `seek(to)`, `setRate`, `setCaptions`, and publishers for `time`, `duration`, `state` (unstarted/buffering/playing/paused/ended/ad), `error(code)`.
- `YouTubeIFramePlayer`: **one `WKWebView` created at app launch and reused** for every video (warm start). Loads a local HTML page with the IFrame API, `playsinline=1`, `controls=0`, `rel=0`, `iv_load_policy=3`, `cc_load_policy` from the setting. JS ↔ Swift bridge via `WKScriptMessageHandler`; time is polled at 4 Hz while playing.
- Errors 2/5/100/101/150 → video goes to SEEN, toast "That video isn't available anymore." and moves on to the next video (or Home).

## Behavior
**Portrait layout (top to bottom)**
1. 16:9 player. Tap → show/hide controls (auto-hide after 3 s while playing).
   Controls: no play button of our own; tap the middle to play/pause (D70), −10/+10 (double-tap left/right third), seek bar with elapsed/remaining time, speed (1x label), CC, fullscreen, and a ⌄ close button top-left.
2. Title (up to 3 lines), creator · "2 days ago".
3. **Up Next** header with "3 videos · 28 min", then the remaining videos as compact rows (thumbnail, title, creator, duration, progress bar). Up/down arrows on each card to reorder (also reorders Home, D69).

**Leaving vs switching**
- ⌄ / swipe down / back → Home; this video keeps its progress (accidental exit).
- Tap an Up Next row → alert **"Play next video? You won't be able to come back to this one."** [Play] [Cancel]. On Play: current video → SEEN (D12), the tapped one starts. If the current video hasn't started yet (0 s), no alert, no SEEN.
- Reaching the last 60 s (by playing or seeking, D38) → marked watched. It stays on screen until it ends or you leave.

**End of video**
- Not the last: a **Next video ▸** button over the player with the next title (no autoplay, no countdown).
- Last one: "That's today's shipment" overlay, then auto-return to Home after 3 s (D37).

**Fullscreen**
- Rotating to landscape or tapping ⤢ → full-bleed video, same controls, Up Next hidden. Rotating back or tapping ⤡ → portrait.
- Double-tap left/right third → −10/+10 s with a ripple + "10 seconds" label, as on YouTube (also works in portrait).

**Resume:** a started video resumes at its saved position minus 3 s.

## Acceptance criteria
- [ ] P1 Tapping a Home card opens the player and video starts < 1.5 s after the tap on device (warm player).
- [x] P2 Double-tap right/left seeks ±10 s in portrait and fullscreen.
- [x] P3 Rotating to landscape enters fullscreen; rotating back exits.
- [x] P4 The speed menu offers 1/1.25/1.5/2; the choice persists to the next video and after relaunch. Same for CC.
- [x] P5 Closing the player mid-video → Home card shows the white progress bar; reopening resumes ~3 s before that point.
- [ ] P6 Locking the phone pauses playback; progress is saved.
- [x] P7 Tapping an Up Next video shows the confirmation; confirming makes the previous video disappear permanently; cancelling keeps playing.
- [x] P8 Seeking into the last 60 s, then closing → the video is gone from Home.
- [x] P9 When a non-last video ends, Next video appears and nothing autoplays.
- [x] P10 When the last video ends, the app returns Home on its own within ~3 s, showing the verse and countdown.
- [x] P11 An unavailable video (fixture ID returning error 150) is skipped with a toast and never shown again.
- [x] P12 Reordering Up Next is reflected on Home.
- [ ] P13 No comments, likes, related videos or links to YouTube are reachable anywhere in the player (description shown, D35; its links open in Safari).

## Verification (2026-10-27)
- 65 unit tests pass. `PlayerControllerTests` (fake player) cover resume −3 s (P5), progress + played seconds, last-60-s and seek-to-end (P8), switch confirmation (P7), Next video with no autoplay (P9), last video → all done (P10), unplayable → dropped + next (P11), Up Next reorder → Home (P12), speed/CC remembered (P4), pause on leave (P6), and CC re-applied on play.
- Simulator, live YouTube: the real video plays in the embedded official player; our controls show (close, 1×, CC, play/pause, seek bar 0:19/34:28, fullscreen) and auto-hide after 3 s; double-tap right → "10 seconds" bubble and a jump (P2); rotating → fullscreen and back (P3); closing → Home card shows the white progress bar and the header counts only time left.
- Fixed while testing: YouTube switched captions on by itself even with CC off; the CC choice is now re-applied when each video starts playing.
- Known: after a seek or pause YouTube briefly shows its own overlay (title, share, YouTube logo, a suggested-video card). Our touch layer covers the whole video, so none of it is tappable (P13), but it is visible for a moment. Ads can't be skipped, because the skip button sits under the same touch layer.
- Not yet verified: P1 tap-to-play under 1.5 s (needs a device), P6 lock-screen pause by hand, Up Next / Next video by hand (needs a day with 2+ videos; covered by unit tests), P13 beyond the visual check.
- Debug-only: `-seedCreators veritasium,3blue1brown` follows those creators on launch for quick Simulator checks.

## Controls look and speed (2026-11-19, D211 to D216)
Changed on the phone with KJ, build by build, next to recordings of YouTube. This replaces the controls described under Behavior above where they differ.
- **On open (D217):** the controls start hidden and the video just plays. A tap brings them up. The same when the next video starts.
- **Fade:** in over 0.05 s on a touch, out over 0.12 s (also when they hide on their own). The controls stay built while hidden.
- **Shade:** only along the top. No dark shade at the bottom.
- **Bottom row, upright and full screen:** one glass pill on the left with both times ("1:14 / 38:48"); on the right a round mute button, then a round full screen button. Mute is not remembered.
- **Glass:** the pill, mute, full screen and play/pause all sit on the video blurred in gray.
- **Bar, upright:** a 2 pt line on the picture's bottom edge, always there. White while the controls are hidden; red with a knob, and draggable, once they show.
- **Bar, full screen:** under the bottom row, 34 pt up from the screen edge. The controls reach 16 pt past the picture's sides.
- Checked in the Simulator (upright and full screen) and by KJ on the phone. Unit tests cover none of the look.

## Out of scope
Mini-player, background audio, Picture in Picture, AirPlay (all candidates for the later native-player phase), quality picker, chapters, sharing.

## Test plan
- Unit: watched-threshold logic, switch-away/leave state transitions, resume offset, using a `FakeVideoPlayer` that conforms to `VideoPlayer`.
- Simulator: P2–P13 with seeded data, screenshots; rotation via the simulator rotate action.
- Device: P1 timing (on-device timer log), P6.
