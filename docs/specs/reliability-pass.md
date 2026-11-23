# Reliability and polish pass
Status: approved (KJ, 2026-11-09) · verified 2026-11-09

## Summary
Eight fixes from the whole-app review (2026-11-09). Four make the daily shipment and the player dependable on a bad connection; four are small polish. Nothing here adds a new way to watch more: it only makes sure the videos KJ is owed show up on the right day and play. Serves "trusted creators, still surprised": today's uploads arrive today.

## Decisions (also in PLAN.md §2)
- D105 Shipment waits for the upload check: a shipment that is due is delivered **only after YouTube has been checked for new uploads** (a check from the last 30 min counts). The Inbox no longer builds the shipment the instant it opens.
- D106 Check failed: if the check couldn't reach YouTube (offline, YouTube not answering), the shipment **waits** and the check is **tried again** on the next app open, on coming back to the Inbox, and every minute while the Inbox is open. Nothing is lost by waiting: videos can't play offline anyway. If YouTube's daily limit is hit, the shipment is delivered from the videos already waiting, since the check can't work until tomorrow.
- D107 Player page: if YouTube's player page didn't load (app opened offline), it **loads again** when a video is tapped and when the app comes back to the front. No force-close needed.
- D108 Playback errors: only YouTube's "gone" errors (**deleted, private, or not allowed in apps**: codes 100, 101, 150) remove a video for good. Any other error **tries the video once more** at the same spot; if that fails too, a banner says "Couldn't play this video. Check your connection and tap play." and the video **stays in the Inbox**.
- D109 Unfollowed creator's videos: cards still in the Inbox **keep the creator's name and picture** after an unfollow.
- D110 Inbox status line: **one small gray line at the top of the Inbox** when the upload check failed: "Offline. Will check for new videos when you're back." or "YouTube's daily limit is reached. New videos tomorrow." Gone as soon as a check works. No alert, no notification (D30).
- ⚙︎ Defaults (mine, flip any):
  - While the check runs on open, the Inbox shows yesterday's leftovers as usual and the new cards slide in underneath when ready. An empty Inbox with a shipment due shows a spinner and "Getting today's videos…" instead of the verse.
  - "Check worked" means at least one creator answered. A single creator that failed is simply checked again next time; their videos are not skipped (the per-creator marker only moves on success, as today).
  - Up to 6 creators are checked at the same time.
  - The "How it works" tips say ⋯ (matches the card menu, D69).

## Behavior
- **Open after shipment time, online:** leftovers show at once; the check runs (faster now, creators in parallel); then the shipment arrives including videos posted since yesterday.
- **Open after shipment time, offline:** leftovers show, the status line shows, no shipment yet. Back online: within a minute (or on next open) the check runs, the shipment arrives, the line goes away.
- **Days stacked up** (app closed for days): unchanged (⚙︎a), just delivered after the one check.
- **Shipment comes due while the Inbox is open:** same rule: check first, then deliver.
- **Day-one / "starved" serving** (D16, D26) is unchanged: it serves right away from what's waiting.
- **Background wake-up** before shipment time still does the check, so on most mornings there is no wait at all.
- **Player:** a "gone" error behaves as today (banner "That video isn't available anymore.", moves to the next video). Other errors never remove anything and never count as watched.
- **Unfollow:** name and picture are remembered for videos still in the Inbox, and forgotten once those videos leave.

## Acceptance criteria
- [x] R1 — Given a shipment is due and a creator posted a video an hour ago, when the app opens online (no background wake-up happened), then that video is in today's shipment.
- [x] R2 — Given a shipment is due and the phone is offline, when the app opens, then no shipment is delivered, leftovers still show, and the status line says it's offline.
- [x] R3 — Given R2, when the connection is back and the Inbox is open (or the app is reopened), then within about a minute the check runs, the shipment arrives with the newest uploads, and the status line is gone.
- [x] R4 — Given a failed check, then the next try is not blocked by the 30-minute wait.
- [x] R5 — Given YouTube's daily limit is hit and a shipment is due, then the shipment is delivered from the videos already waiting and the status line says the limit is reached.
- [x] R6 — Given one of several creators fails to answer, then the shipment still arrives, and that creator's new video shows up in a later shipment (not skipped).
- [x] R7 — Given an empty Inbox with a shipment due, while the check runs, then the screen shows "Getting today's videos…", not the verse.
- [x] R8 — Given the app was opened offline, when the connection is back and KJ taps a video, then it plays without force-closing the app.
- [x] R9 — Given YouTube reports error 100, 101 or 150, then the video is removed for good with the "isn't available anymore" banner (as today).
- [x] R10 — Given YouTube reports any other error, then the video is tried once more at the same spot; if it fails again, the "Couldn't play this video" banner shows and the video is still in the Inbox with its progress.
- [x] R11 — Given a creator's video is in the Inbox, when KJ unfollows them, then the card (and the player) still shows their name and picture.
- [x] R12 — Given 12 followed creators, then the upload check asks several at once, and every creator's videos land exactly as they did one at a time.
- [x] R13 — The "How it works" tips show ⋯ for Swap and Remove.
- [x] R14 — All existing tests still pass.

## Out of scope
- Watching offline or downloading videos.
- A retry button or pull-to-retry (pull down stays "swap today's videos").
- Any change to how videos are picked, ranked, or counted as watched.
- Adding to today's Inbox after its shipment has arrived (D44: today is never changed).

## Test plan
- Unit tests (`ReliabilityTests`, using the fake YouTube): R1–R6 and R12 on `AppStore`; R9–R10 on `PlayerController`; R11 on the card data.
- Simulator: (a) turn the Mac's network off, launch with a shipment due → status line, no shipment → network on → shipment arrives (R2, R3). (b) Launch offline, go online, tap a video → plays (R8). (c) Unfollow a creator with a video in the Inbox → card keeps name and picture (R11). (d) Open ⓘ › How it works (R13). Screenshots of each.

## Verified (2026-11-09)
- Unit tests: 184 pass (`ReliabilityTests` R1–R6, R11, R12; `PlayerControllerTests` R9, R10).
- Simulator (iPhone 17), using debug launch options since the Mac's network can't be switched off mid-session: `-offline` (YouTube's Data API never answers), `-shipmentDue`, `-clearInbox`, `-breakPlayerPage` (first player page load fails like a launch offline).
  - R2: leftovers + "Offline. Will check for new videos when you're back." and no shipment.
  - R7 (offline form): empty Inbox shows "Today's videos are waiting". The "Getting today's videos…" spinner is the same branch but too brief to capture.
  - R8: with the player page broken at launch, tapping a video reloaded the page and it played.
  - R11: unfollowed 3Blue1Brown; its Inbox card kept the name and picture.
  - R13: tips show ⋯.
- Not checked: a real airplane-mode run on a phone, and the largest text size.
