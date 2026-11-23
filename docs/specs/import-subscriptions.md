# Import YouTube subscriptions
Status: approved

## Summary
A person signs in with Google once, the app reads who they subscribe to on YouTube, and shows that list so they tick only the creators they want to bring over. The ticked ones are followed like any other follow. Nothing is ticked to start with, so every creator is a choice ("trusted creators only", no unconscious carry-over).

## Decisions
- D152 Import uses **Sign in with Google** (the official way), read-only access to the YouTube account. Google "testing" mode for now: up to 100 people added by hand, with Google's "unverified app" warning. A public release needs Google's review first.
- D153 **Nothing is ticked to start.** The person ticks each creator they want. There is a search box to filter the list.
- D156 **Select all** is a round tick with "All" at the top right. It ticks everyone not yet followed, so the person can untick the ones to leave behind. Once all are ticked, the same circle is filled and unticks everyone. With a search typed, both touch only the creators shown. (KJ asked for it after trying the list; D153 first said no Select all.)
- D154 **Sign-in is one time.** The app uses it to read the list, then forgets it. Nothing about the Google account is saved, only the creators that were picked. Importing again means signing in again.
- D155 **Where the button is:** "Import from YouTube" on the Following page when no one is followed yet, and a row in Settings for later.
- D160 **Swiping down does not close the list.** Only Cancel (or Continue) closes it, since scrolling back to the top kept closing it by mistake.
- ⚙︎ Defaults: list is A to Z; creators already followed show "Following ✓" and can't be ticked; picked creators go to the bottom of the rank in the order they were ticked; no limit on how many; no new libraries (Apple's own sign-in sheet).

## Behavior
**Getting there**
- Following, when the list is empty: an **Import from YouTube** button under "Follow creators you trust…".
- Settings: a row **Import YouTube subscriptions**.
- If the build has no Google client ID, both are hidden.

**Sign-in**
- Tapping the button opens Apple's sign-in sheet on Google's page. The app asks only to *view* the YouTube account (`youtube.readonly`).
- Cancel or closing the sheet goes back with no message.
- Google says no (not a test user, access denied): "Couldn't sign in to Google." with **Try again**.

**Pick list** (a sheet)
- Title "Pick creators", **Cancel** on the left. A blue **Continue (3)** button shows at the bottom right once at least one creator is ticked, with the count (D157); it follows the picks. It is hidden while the search box has text, so it never looks like the way to save one creator, and comes back when the search is cleared (D175).
- A spinner with "Getting your subscriptions…" until the whole list is loaded (50 at a time behind the scenes).
- Rows: avatar, name, a round tick on the right. Tap anywhere on the row to tick or untick, with the subtle follow haptic.
- Search box at the top filters by name as you type. Ticks are kept while filtering.
- Already followed: "Following ✓" in gray, no tick.
- No subscriptions: "No subscriptions found on this account."
- Offline or YouTube error: message with **Retry**. Quota used up: "YouTube is resting until tomorrow."

**After tapping Continue**
- The sheet closes and the app **opens the Following page**, even when the import was started from Settings (D158). A bar at the bottom says "12 creators added. Hold and drag to rank them." with a green tick, for 5 seconds or until it is tapped (in Random mode just "12 creators added."). The bar is one shade lighter gray than the cards.
- The picked creators appear at the bottom of Following, in the order they were ticked.
- Each one is followed through the same code as a normal follow, so the existing rules apply with no changes: day one brings one starter video each (D79, D80), later follows bring only new uploads (D92), and a short day can be filled (D136).
- The Google sign-in is thrown away right then.

**What is saved**
- Only new `Creator` rows, same as a normal follow. No Google account, token, email, or full subscription list is stored.

**Setup KJ does once (I'll walk through it)**
- In Google Cloud (same project as the YouTube key): turn on the sign-in screen in testing mode, add KJ's Google account as a test user, and make one "iOS" client ID for KJ Tube (KJ Tube Dev uses the same one).
- `GOOGLE_CLIENT_ID` goes in `Secrets.xcconfig`. It is optional.

## Acceptance criteria
- [ ] AC1 With no creators followed, Following shows **Import from YouTube**. Settings shows **Import YouTube subscriptions**. With no client ID in the build, neither shows.
- [ ] AC2 Tapping it opens Google sign-in. Cancelling returns to where the person was, with no error.
- [ ] AC3 After sign-in, the pick list shows every subscription (tested with more than 50, so paging works), A to Z, with avatar and name, none ticked.
- [ ] AC4 Typing in the search box filters by name; ticks made before filtering are still there after clearing it.
- [ ] AC5 A creator already followed shows "Following ✓" and can't be ticked or added twice.
- [ ] AC6 The blue Continue button shows at the bottom right with the number ticked, and is not there at 0.
- [ ] AC7 Tapping Continue adds exactly the ticked creators to the bottom of Following in tick order, and the order is still there after a relaunch.
- [ ] AC8 Imported creators get videos by the same rules as a normal follow (starter on day one, nothing old after day one).
- [ ] AC9 After the import, no Google token or account detail is stored on the phone; importing again asks for sign-in again.
- [ ] AC10 Offline, or a YouTube error while loading the list, shows a message with Retry; nothing is followed.
- [ ] AC11 An account with no subscriptions shows "No subscriptions found on this account."
- [ ] AC12 The "All" circle at the top right ticks every creator not yet followed and shows as ticked; tapping it again unticks them. With a search typed, both touch only the creators shown.
- [ ] AC13 A creator already followed looks like the other rows (same name and picture brightness, full divider) with a small gray "✓ Following" on the right.
- [ ] AC14 After Continue, the app is on the Following page (also when started from Settings) and shows "N creators added. Hold and drag to rank them." for about 5 seconds.
- [ ] AC15 Swiping down on the pick list does not close it, and the list does not jump when Continue appears or goes away.

## Out of scope
- Keeping in sync with YouTube (new subscriptions don't show up by themselves).
- Unsubscribing or changing anything on YouTube.
- Staying signed in, showing the Google account, or any other use of the sign-in.
- Google's public review, privacy policy and demo video (needed only before a public release).
- Importing from a file or a pasted channel link.

## Test plan
- Unit: decoding the subscriptions response from JSON fixtures; paging across 3 pages; A to Z sort; filter keeps ticks; already-followed marking; tick order becomes rank order; nothing followed on error; sign-in link is built correctly (client ID, read-only scope, PKCE) and the returned code is read correctly; token is not kept after import. No live network in tests.
- By hand (needs a real Google account, so on KJ's phone or the Simulator with KJ signing in): AC2, AC3, AC7 against the real account.
