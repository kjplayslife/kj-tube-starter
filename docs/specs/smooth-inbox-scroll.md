# Smooth Inbox scroll
Status: built, waiting for KJ to try it on the phone (KJ OK'd "whatever you think is best", 2026-11-09)

## Summary
With 4 or more cards, scrolling the Inbox right after opening the app was choppy. Serves "native, fast iPhone app": the scroll should feel perfectly clean.

## Causes found
1. Each card read its thumbnail from disk on the main thread as it scrolled in, and the picture was unpacked lazily at first draw, also on the main thread.
2. Each card did its own SwiftData fetch of every creator, each time it was drawn.
3. Any store change (view counts arriving just after launch, the minute ticking) redrew every card.

## Decisions (also in PLAN.md §2)
- D99 Smooth Inbox scroll: **pictures load and decode off the main thread**, shrunk to card size (≤ 1150 px). Only the first 3 cards' pictures are read before the first frame, so they still never pop in (speed-and-polish Q3). **Cards redraw only when their own info changes.** Creators are looked up once per list, not once per card.

## Acceptance criteria
- [ ] S1 — Given 5+ videos in the Inbox after a cold start, when KJ scrolls to the bottom and back, then it scrolls without visible hitches.
- [ ] S2 — Given a cold start, then the first cards show their thumbnails in the first frame (no pop-in).
- [ ] S3 — Cards further down may show a gray box for a moment the very first time, then the picture.
- [ ] S4 — Move up/down, Swap, Remove and tap-to-play still act on the right video after reordering.
- [ ] S5 — Unit: a 1280 × 720 thumbnail decodes to 1150 px wide; an avatar keeps its size.
