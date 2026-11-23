# Building KJ Tube for Android

This explains how the iPhone app works so you can rebuild it on Android. The Swift code in this repo is the reference; file names below point to the part that does each job.

## The idea in one minute

- You **follow** a handful of creators and put them in order of how much you care.
- You pick a **daily amount**: 30, 60 or 90 minutes (weekdays and weekends separately).
- Once a day, at a time you choose (6 am by default), the app delivers a **shipment**: enough new videos from your creators to fill today's amount. That list is the **Inbox**.
- Watch one and it's gone. When the Inbox is empty you see a short verse and a countdown to tomorrow. There is nothing else to tap.
- No Shorts, no live streams, no recommendations, no comments, no search for videos. Only search for creators.

Three tabs: **Inbox · Following · Settings**. The player opens over the Inbox.

## The pieces

| Piece | iPhone file | Job |
|---|---|---|
| Engine | `Engine/ShipmentEngine.swift`, `ShipmentModels.swift` | All the rules. Takes state + settings + the current time, returns new state. No UI, no network, no clock of its own |
| YouTube client | `YouTube/YouTubeClient.swift` | The five API calls and the Shorts check |
| Uploads loader | `YouTube/UploadsLoader.swift` | "Give me this creator's new, eligible videos" |
| Store | `Store/AppStore.swift` | Saves state, decides when to ask YouTube, hands data to the screens |
| Player | `Player/YouTubeIFramePlayer.swift` | YouTube's embedded player inside a web view |

**Build order that works:** engine with unit tests → YouTube client → Following screen → Inbox → player → Settings → background wake-up → polish.

Port the engine first, as plain Kotlin with no Android imports, and port `ShipmentEngineTests.swift` along with it. Always pass "now" in as a parameter so tests can pretend it is any day and time. If the engine is right, the rest is screens.

## What the app remembers

All on the phone. No account, no server, no cloud sync.

**Creators** (ordered list; the order is the rank): channel ID, name, picture URL, subscriber count, "last upload" date, plus two per-creator switches: *Watch in Order* and *Any Length*.

**Engine state** (see `ShipmentState`):

- `home`: today's Inbox, in the person's own order. Each entry is a video plus how many seconds were watched.
- `backlog`: eligible videos waiting to be picked.
- `seen`: a set of video IDs that must **never** be shown again. It only grows.
- `lastShipment`: when the last shipment was delivered.
- `watchedSinceShipment`, `refreshesUsed`, `refreshDayStart`: for the refresh rule.
- `fetchedThrough`: per creator, the publish time of the newest upload already looked at.
- `lastUploadCheck`, `lastOpenedAt`: for saving quota.
- `starters`: IDs of "welcome" videos (explained below).
- `watchLog`: seconds watched per calendar day, for the stats chart.

A video is just: ID, creator ID, title, length, publish date. Thumbnails come from `https://i.ytimg.com/vi/<id>/hqdefault.jpg`, so there is no need to store them.

On Android: Room for creators and a single JSON blob (DataStore or a file) for the engine state is enough. Save the backlog and `fetchedThrough` in the **same write**, or a crash between the two can lose videos for good.

## The life of a video

```
YouTube upload → (eligible?) → backlog → Inbox → SEEN
                     no ↓          ↓ older than 30 days
                   ignored        SEEN
```

A video goes to **SEEN** when:

- you leave it with 60 seconds or less remaining (that counts as watched),
- you remove it from the Inbox (⋯ menu, with an Undo bar),
- it's swapped away by a refresh,
- you confirm jumping to another video in the middle of it,
- it waited in the backlog for 30 days,
- the player says it can't be embedded (errors 101 or 150).

Closing the player early or leaving the app **keeps** the video in the Inbox with its progress bar.

## Which videos are eligible

From a followed creator, not in SEEN, and all of these (`UploadsLoader.swift`):

| Rule | How to tell |
|---|---|
| Not live or upcoming | `snippet.liveBroadcastContent == "none"` |
| Not a stream replay | the video has no `liveStreamingDetails` |
| Public | `status.privacyStatus == "public"` |
| Has a length | `contentDetails.duration` > 0 (ISO 8601, like `PT12M30S`) |
| Can be embedded | `status.embeddable == true` |
| Not a Short | see next section |

One `videos.list` call with `part=snippet,contentDetails,status,liveStreamingDetails` answers all but the last.

## Filtering out Shorts

The API has no "is this a Short" field, and length alone isn't reliable: plenty of normal videos are under 3 minutes.

What works: send a **HEAD** request to `https://www.youtube.com/shorts/<videoId>` and follow redirects.

- Final URL still starts with `/shorts/` and status is 200 → it's a Short. Drop it.
- It was redirected to `/watch?v=…` → normal video. Keep it.

To keep this cheap:

- Shorts are at most 3 minutes long, so **only check videos of 180 seconds or less**. Everything longer is kept without a request.
- This is a plain web request, not an API call, so it costs **no quota**.
- Do the cheap API rules first, then the Shorts check only on what's left.
- If the request fails (offline), treat that creator's check as failed and try again next time. Don't guess.

With OkHttp: `followRedirects(true)`, then look at `response.request.url.encodedPath`.

## Getting videos into the backlog

**The uploads playlist trick.** Every channel has a hidden playlist of all its uploads. Its ID is the channel ID with the first two letters `UC` changed to `UU`. So `playlistItems.list?part=contentDetails&playlistId=UU…&maxResults=15` lists a creator's newest uploads for **1 unit**. Never use `search.list` for this (100 units).

**The regular check** (`AppStore.catchUp` → `UploadsLoader.eligibleUploads`):

1. For each creator, list the newest 15 uploads (a few creators at a time, not all at once).
2. Keep only the ones published after that creator's `fetchedThrough` time.
3. Gather every new video ID from all creators and ask for details **50 per call**.
4. Apply the eligibility rules and the Shorts check.
5. Add what passes to the backlog and move each creator's `fetchedThrough` forward, in one save.

If one creator's request fails, the others still go through, and the failed creator's `fetchedThrough` stays where it was so nothing is skipped.

**Following someone new:**

- **Before anything has ever been delivered** (first run), or while today's Inbox is short or empty: bring their **latest eligible video** as a *starter*. It looks back up to 50 uploads to find one.
- **Otherwise:** bring nothing old. Only videos posted from now on. (People have usually already seen a creator's old videos.)

A **starter** is a welcome video with lower standing: it is picked after real new uploads, it gets one shipment to fit in, and it's dropped if that creator posts something new first.

**Unfollowing** removes that creator's videos from the backlog. Anything already in the Inbox stays.

## The daily shipment

This is the heart of the app (`ShipmentEngine.ship`). At shipment time:

```
budget = today's minutes (weekday or weekend; Friday can count as weekend)
slack  = 15 minutes

sort the backlog: new uploads before starters,
                  then by creator rank (top of the Following list first),
                  then newest first
                  ("Random" mode skips the rank step: newest first only)
for creators with Watch in Order on: their videos keep their slots, but oldest first

picked = []
for each video in that order:
    if video is longer than budget + slack:
        if its creator has Any Length on and picked is empty:
            picked = [video]; stop          # it becomes the whole day
        else:
            skip it                         # never served; it will expire
    else if total(picked) + video > budget + slack:
        stop                                # rank wins: don't skip ahead to a shorter one
    else:
        add it to picked
        if total(picked) >= budget: stop

Inbox = what was left from yesterday (in the person's order) + picked
```

Details that matter:

- **Leftovers carry over.** Unwatched videos stay at the top and the new picks go underneath. Leftovers don't count against today's budget, and there is no cap.
- **Missed days stack.** If the app wasn't opened for three days, the three owed shipments are applied one after another when it opens (`applyDueShipments`).
- **A short day is fine.** If the backlog can't fill the budget, deliver what there is and show a small "That's all for today" note under the last card.
- **Nothing at all:** show "No new videos from your creators" with a button to Following.
- **The first shipment** doesn't wait for 6 am: at the end of first run the person taps **Load my Inbox** and gets it at once.
- **Check YouTube before delivering.** A due shipment waits for the upload check to finish, so today's uploads arrive today. If offline, deliver from the backlog as it is.

## Refresh ("swap today's videos")

Pulling down on the Inbox offers to swap the whole list. Allowed only when **all** are true (`refreshCheck`):

- refreshes left today > 0 (setting: 0, 1 or 2 a day; the count starts over at shipment time),
- 60 seconds or less watched since the shipment (no "watch the best one, then swap"),
- the backlog can fill at least `budget − 15 min`.

After a confirmation, every Inbox video goes to SEEN and the picker runs again on the backlog. If the backlog is too thin, no refresh is used; say "Not enough new videos" instead. There is also a one-video version (**swap** from the ⋯ menu) that uses the same daily count.

## Settings, with friction

The point is to make "just a little more" hard (`SettingsPolicy.swift`):

| Setting | Choices | Rule |
|---|---|---|
| Weekday minutes | 30 / 60 / 90 | Lower any time. Raise once per 7 days |
| Weekend minutes | 30 / 60 / 90 | Same, own clock |
| Friday is weekend | on / off | Off any time. On once per 7 days |
| Shipment time | whole hours | Once per 7 days; starts with the next shipment |
| Refreshes per day | 0 / 1 / 2 | Lower any time. Raise once per 7 days |
| Creator order | Ranked / Random | Free |

Each limit has its own 7-day clock. A locked control says when it unlocks.

## Saving quota

The whole app shares 10,000 units a day (see [YOUTUBE_API_SETUP.md](YOUTUBE_API_SETUP.md)). What keeps one person at about 70 units a day:

1. **Check for uploads twice a day, not on every open.** Once when the shipment is due and once 12 hours later. Save `lastUploadCheck` so reopening the app asks nothing. A check up to 30 minutes early counts, so the background wake-up can do the morning one.
2. **Uploads playlist, never search**, for new videos: 1 unit per creator per check.
3. **Batch details:** all new videos from all creators, 50 IDs per `videos.list` call. Usually 1 unit for everyone.
4. **Per-creator cursor** (`fetchedThrough`): only uploads newer than the last one looked at get a details call. On most checks most creators have nothing new.
5. **Shorts check costs nothing** and only runs on videos of 3 minutes or less.
6. **Search only when the person presses Search**, never while typing. It is the one expensive call (100 units, plus 1 to fetch subscriber counts for the results).
7. **Free shortcuts in the search box** (`YouTubeLink.swift`): a pasted channel link, `@handle` or video link is looked up with `channels.list` (1 unit) and skips search.
8. **Dormant installs ask nothing.** If the app hasn't been opened in over a week, the background wake-up does no checks and stops rescheduling itself. Opening the app starts everything again.
9. **View counts and descriptions** (shown on cards) are fetched for the Inbox videos only, in one call.

With 50 followed creators: 2 checks × (50 playlist calls + 1 or 2 details calls) ≈ 100 units a day at the very most, less in practice.

## Screens

**Inbox.** YouTube-style cards: 16:9 thumbnail with a length badge, a progress bar if started, creator picture, title, "Creator · views · age", and a ⋯ menu (Move up, Move down, Swap, Remove). Hold and drag to reorder. Pull down to refresh. An ⓘ button opens a page explaining the rules and showing a watch-time chart for the week. Empty states: all watched (verse + countdown), nothing found (button to Following), first run (welcome).

**Following.** A search box on top; results show picture, name, subscribers and a Follow button. Below it, the followed list: drag to reorder (that is the rank), swipe to unfollow with an Undo bar. Each row shows "Last upload 3d ago" (long-form videos only) and the two switches, Watch in Order and Any Length.

**Settings.** The limits table above, creator order, Import from YouTube, About.

**Player.** Video on top; below it the title, views, creator and description, then the rest of today's list. Tapping another video asks "Play next video? You won't be able to come back to this one." When a video ends, a **Next video** button appears; there is no autoplay. After the last one, back to the Inbox. Progress is saved every few seconds so an accidental exit loses nothing.

**First run.** Follow a few creators (or import), pick a daily amount, get the first Inbox immediately.

## The player on Android

YouTube only allows playback through its own embedded player. On Android that means the **IFrame Player API inside a WebView**. The easiest route is the open-source [android-youtube-player](https://github.com/PierfrancescoSoffritti/android-youtube-player) library, which wraps exactly that and gives you play/pause/seek, current time, state changes and error codes.

What you need from it:

- **Current time**, a few times a second: to save progress, and to mark a video watched at 60 seconds from the end.
- **State changes:** ended (show Next video), playing, paused, buffering.
- **Errors 101 and 150:** the owner blocked embedding. Send the video to SEEN and move on.
- Keep **one** player view alive and load new video IDs into it. Creating a new WebView per video is slow.

If you plan to publish: leave YouTube's own controls visible (`controls=1`), don't draw anything over the video, and don't block or skip its ads. The iPhone code has two flavours behind `AppConfig.isPublic`; follow the `isPublic == true` paths.

## Android equivalents

| iPhone | Android |
|---|---|
| SwiftUI | Jetpack Compose |
| `@Observable` store | `ViewModel` + `StateFlow` |
| SwiftData / saved JSON | Room, DataStore |
| `URLSession` + `Codable` | OkHttp or Ktor + kotlinx.serialization |
| `BGAppRefreshTask` | WorkManager (periodic work, about 30 min before shipment time) |
| `WKWebView` + IFrame API | WebView + IFrame API (android-youtube-player) |
| `Secrets.xcconfig` | `local.properties` → `BuildConfig` |
| Swift Testing | JUnit + kotlinx-coroutines-test |

Background work is never guaranteed on either platform. Treat it as a head start: whenever the app opens, run the same catch-up (check uploads if due, deliver if due).

## Good first milestone

A screen with a search box, a Follow button, and a list that shows each followed creator's newest eligible long-form video. That proves the API key, the uploads playlist trick, the eligibility rules and the Shorts check. After that, drop in the engine and you have the Inbox.
