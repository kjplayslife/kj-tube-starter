# YouTube API setup

The app has no server. Each install talks straight to the **YouTube Data API v3** with one API key that is built into the app. It's free, with a daily limit.

## 1. Get an API key (required)

1. Go to [console.cloud.google.com](https://console.cloud.google.com) and make a new project.
2. **APIs & Services → Library →** search "YouTube Data API v3" → **Enable**.
3. **APIs & Services → Credentials → Create credentials → API key.**
4. Restrict the key (click it):
   - **API restrictions:** YouTube Data API v3 only.
   - **Application restrictions:** *Android apps*. Add your app's package name and the SHA-1 of your signing certificate (`./gradlew signingReport` prints it). Add both your debug and release SHA-1.
5. With an Android restriction, every request must carry two headers or Google answers 403:
   - `X-Android-Package: your.package.name`
   - `X-Android-Cert: <SHA-1, hex, no colons>`

   (The iPhone app does the same with `X-Ios-Bundle-Identifier`; see `YouTubeClient.swift`.)
6. Keep the key out of git. On Android, put it in `local.properties` (already gitignored by default) and read it into `BuildConfig`:

   ```
   # local.properties
   YOUTUBE_API_KEY=your-key-here
   ```

A key inside an app can always be dug out by someone determined. The package + SHA-1 restriction is what makes a stolen key useless, so don't skip it.

## 2. Know the quota

Every project gets **10,000 units a day**, shared by everyone using your app.

| Call | Used for | Cost |
|---|---|---|
| `search.list` (type=channel) | Finding a creator by name | **100** |
| `channels.list` | Creator name, picture, subscriber count; look up by @handle | 1 |
| `playlistItems.list` | A creator's newest uploads | 1 |
| `videos.list` | Length, live/Short clues, embeddable (up to 50 videos per call) | 1 |
| `subscriptions.list` | Import from YouTube (50 per page) | 1 |

Search is the expensive one: 100 searches use the whole day's quota. Everything else is cheap. The guide's "Saving quota" section shows how the app stays around 70 units per person per day. For a handful of friends the free quota is plenty. For more, Google has an audit form to ask for a higher limit.

When the quota runs out the API answers 403 with reason `quotaExceeded`. Show a friendly "try again tomorrow" message (quota resets at midnight Pacific time).

## 3. Google sign-in for "Import from YouTube" (optional)

Lets a person pick creators from the channels they already subscribe to. Skip it for a first version.

1. **APIs & Services → OAuth consent screen:** set it up, add the scope `https://www.googleapis.com/auth/youtube.readonly`. While the app is in "Testing", add each friend's Google account as a test user.
2. **Credentials → Create credentials → OAuth client ID → Android**, with your package name and SHA-1.
3. In the app, use Google's sign-in for Android (Credential Manager / `AuthorizationClient`) to ask for that one scope and get an access token.
4. Call `GET https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&maxResults=50&order=alphabetical` with `Authorization: Bearer <token>`, following `nextPageToken` until it's gone.
5. Throw the token away afterwards. The app only needs the list once; it never stays signed in.

`youtube.readonly` is a "sensitive" scope: to offer it to the public (not just test users) Google must verify the app.
