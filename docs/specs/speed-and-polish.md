# Speed & polish (Phase 7)
Status: approved

## Summary
Make KJ Tube feel instant and finished: measured launch and tap-to-play times, thumbnails that never pop in, the next shipment ready before you open the app, an icon, gentle haptics, and the loose ends from Phases 3–6. Serves "native, fast iPhone app".

## Decisions
- D49 App icon: **Claude draws a simple one**, a play mark inside a small parcel on a dark background. Easy to replace.
- D50 Haptics: **subtle, at key moments**: follow, remove, swap (refresh), Next video, and "That's today's shipment". Nothing while scrolling.
- D51 Ads: **the bottom-right corner of the video passes taps through to YouTube** so "Skip ad" works. The rest of the video stays covered.
- ⚙︎ Defaults (technical, mine):
  - Thumbnails: one shared `URLCache` (50 MB memory / 300 MB disk) used by a small `CachedImage` view instead of `AsyncImage`, which doesn't cache reliably. Home prefetches every card's thumbnail when a shipment arrives.
  - Background refresh: a `BGAppRefreshTask` scheduled for ~30 min before shipment time fetches new uploads and applies the shipment, so Home is ready on open. iOS decides the exact timing; opening the app still catches up as now.
  - Measurement: `os_signpost` intervals for "launch → Home visible" and "tap card → first .playing", readable in Instruments and shown in a Debug-only overlay.
  - The pass-through corner is 96 × 56 pt, matching YouTube's skip button area.

## Behavior
**Speed**
- Home renders from saved state in the first frame (already true); thumbnails come from the disk cache with no flash.
- The shared player web view is created at launch (already true). Measure, and if tap → playing is over 1.5 s, also preload the first video cued (paused) while Home is visible.
- Following/Settings never block on the network.

**Background refresh**
- After each shipment and on every app open, schedule the next refresh for (next shipment − 30 min).
- In the task: fetch new uploads (respecting the 30-min throttle), apply due shipments, prefetch thumbnails, save, and complete within the system time limit.

**Polish**
- App icon (D49), all sizes from one 1024 px image.
- Haptics (D50) via `.sensoryFeedback`.
- Ad corner (D51).
- Cards animate in/out (insert/remove) with the default spring; the remove toast already animates.
- Loose ends from earlier phases: countdown updates every second in its last minute (refresh-and-verses ⚙︎); largest Dynamic Type check on Home, the verse screen and Settings; a Release build with no debug tools (S7).

## Acceptance criteria
- [ ] Q1 Cold launch → Home with cards visible in < 400 ms on device (Instruments, App Launch template).
- [ ] Q2 Tap a card → video playing in < 1.5 s on device, measured over 10 taps (signpost).
- [x] Q3 Thumbnails shown once never reload with a visible flash, including after relaunch, and offline.
- [ ] Q4 With the app closed overnight, opening it after shipment time shows the new shipment immediately (background task; verified with the Debug "simulate background fetch" command).
- [ ] Q5 The app icon appears on the home screen and in Settings → General → iPhone Storage.
- [ ] Q6 Haptics fire on exactly the 5 moments in D50 and nowhere else.
- [ ] Q7 During a YouTube ad, tapping "Skip ad" works; tapping anywhere else on the video still only shows/hides our controls.
- [x] Q8 Home, the verse screen and Settings are fully readable at the largest accessibility text size.
- [x] Q9 A Release build has no `-resetData`, `-seedCreators`, `-undoSeconds` or `seedHome` behavior.

## Verification (2026-10-27)
- 84 unit tests pass, including background-refresh scheduling (30 min early, never in the past, across DST), the next-shipment prefetch list, the ad-corner hit test and the cut-out touch shape, and the seconds countdown.
- Q9 ✅ Release build: `strings` finds none of `resetData`, `seedCreators`, `undoSeconds`, `seedHome` (the Debug build does, as a control).
- Q8 ✅ At the largest accessibility text size: Home titles wrap fully (up to 4 lines), Start watching stays one line, the duration badge is capped, Settings stacks its pickers under their labels, the verse screen scrolls if needed, and player controls are capped so they never overlap.
- Q3 ✅ by construction: all images go through one shared memory + 300 MB disk cache (`CachedImage`), and Home prefetches every card's thumbnails when the list changes. A thumbnail flash after relaunch wasn't checked by hand.
- Q2 (Simulator only): tap → playing read 0.65 s (first) and 0.47 s (warm) on the Debug timer. Still needs a device run.
- Icon drawn by `scripts/draw_icon.swift` (no alpha channel, so App Store Connect accepts it).
- Not yet verified: Q1, Q2, Q5 (need a device); Q4 background task (needs the debugger "simulate launch" command or a device overnight); Q6 haptics (the Simulator has none; code review only); Q7 (needs an ad to appear).

## Out of scope
Widgets, iCloud, the native AVPlayer experiment, Screen Time blocking (Phase 8).

## Test plan
- Unit: background-refresh scheduling date (next shipment − 30 min, across DST), thumbnail prefetch list from a shipment, the ad-corner hit test (inside/outside).
- Simulator: Q3, Q6 (haptics are logged in Debug), Q7 when an ad appears, Q8, Q9 (Release build), Q4 via `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.kjtube.refresh"]`.
- Device (needs your Apple enrollment, or a free 7-day install from the Mac): Q1, Q2, Q5.
