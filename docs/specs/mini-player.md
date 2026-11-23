# Mini player
Status: approved (KJ tried it on the phone build by build and said "merge", 2026-11-12)

## Summary
Pull the player down and the video shrinks into a small card in the bottom right corner and **keeps playing** while the Inbox, Following and Settings are used, like YouTube's. KJ asked to try it as a personal build ("this is a personal build for me. We won't make this public yet"), then kept it. This spec was written after the fact from what KJ approved on the phone.

## Decisions (also in PLAN.md §2)
- D164 The drag down looks like YouTube's: the video shrinks toward the bottom right, the page under it is gone in the first bit of the drag, the Inbox shows behind.
- D165 The small player keeps playing over every tab. YouTube's 200 × 200 minimum for embeds (D77) is set aside: the app is personal and not public.
- D166 The video's thumbnail shows until the video really plays, not a black screen.
- D167 The small player stays in the bottom right. Slide it right to close; it moves one to one with the finger. Drag-to-any-corner was tried twice and dropped. **Changed by D186.**
- D186 (KJ, 2026-11-17) The small player follows the finger anywhere and glides to the nearest of the four corners when let go. Pushed out past the edge it sits on, far enough or with a flick, it slides off that edge and closes.
- D168 The full screen button's touch area is the whole bottom right corner of the video.

## Behavior
- **Size and spot:** a rounded card 45% of the screen wide, 8 pt from the right edge, 16 pt above the tab bar.
- **Getting there:** drag the video down more than 200 pt, or flick. A shorter drag springs back.
- **On the card:** dark see-through round buttons in the top corners, play/pause on the left, X on the right. They show only once the card rests in its spot, and go at once when it opens.
- **Opening it again:** tap the card.
- **Moving it (D186):** drag it anywhere; let go and it glides to the nearest corner, counting a flick. Top corners sit just under the status bar.
- **Closing it:** the X, or push it out past the edge it sits on (left, right, up or down). Far enough or a flick and it glides off that edge and the video stops; a short push springs back. No fade.
- **Another video:** tapping an Inbox card closes the small player and opens that video.
- **Full screen:** only from the full player; the small player stays upright.
- The player sits on top of the tabs, not in a full-screen cover.

## Acceptance criteria
- [x] M1 — Dragging the video down shrinks it into the corner and it keeps playing; the tabs and the Inbox work behind it. (Simulator)
- [x] M2 — Pause on the card pauses; a tap on the card opens the full player, still playing. (Simulator)
- [x] M3 — Tapping another Inbox card opens that video in the full player. (Simulator)
- [x] M4 — The X closes it and the video stops. (Simulator)
- [x] M5 — Sliding it right moves it with the finger from the first touch and closes it. (KJ, on the phone)
- [x] M6 — The buttons show only at rest and vanish at once on open. (KJ, on the phone)
- [x] M7 — The thumbnail shows while a video opens. (Simulator)
- [x] M8 — A tap beside the full screen icon goes full screen; with the controls hidden, a tap in that corner brings them up. (Simulator)
- [x] M9 — Opening a video still slides up from the tapped card with no stutter (D138, D163). (Simulator)

## Out of scope
Tucking it at the side with a tab (YouTube does both), a title beside it, Picture in Picture outside the app.

## Not checked yet
- What the shipment and watched rules do when a video ends while it is small (the same player code runs, so it should match the full player).
- Undo bars and the keyboard can sit under the small player.
