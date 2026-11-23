# KJ Tube (open starter)

KJ Tube is an iPhone app for watching YouTube on purpose. You follow a few creators, set how many minutes a day you want, and each morning the app delivers one short list of their new videos: the **Inbox**. When the list is watched, there is nothing left until tomorrow. No feed, no recommendations, no Shorts.

This repo is a cleaned-up copy of the iPhone app's source, shared so others can build their own version, starting with **Android**. All keys, account IDs and personal details have been replaced with placeholders.

## Start here

- **[docs/ANDROID_GUIDE.md](docs/ANDROID_GUIDE.md)**: how the app works, rule by rule, and how to rebuild it on Android. Read this first.
- **[docs/YOUTUBE_API_SETUP.md](docs/YOUTUBE_API_SETUP.md)**: getting your own YouTube API key (free) and the optional Google sign-in.
- [docs/specs/](docs/specs/): the original feature notes with acceptance checks. They mention decision numbers like "D99" from a private planning log; you can ignore the numbers.

## What's in here

| Path | What it is |
|---|---|
| `KJTube/KJTube/Engine/` | The rules: daily budget, picking videos, refresh, "seen". Pure Swift, no UI, no network. **Port this first.** |
| `KJTube/KJTube/YouTube/` | Every call to the YouTube Data API, the Shorts check, Google sign-in for importing subscriptions |
| `KJTube/KJTube/Store/` | Glue: saves state, decides when to ask YouTube, feeds the screens |
| `KJTube/KJTube/Home`, `Following`, `Settings`, `Player`, `FirstRun` | The screens (SwiftUI) |
| `KJTube/KJTubeTests/` | Unit tests. `ShipmentEngineTests.swift` is the best written description of the rules |
| `scripts/sim.sh` | Build, test and run in the iOS Simulator |

## Running the iPhone app (optional, needs a Mac with Xcode 26+)

1. `cp KJTube/Secrets.example.xcconfig KJTube/Secrets.xcconfig` and put your YouTube API key in it.
2. In `KJTube/Config/App.xcconfig`, change `APP_BUNDLE_ID` to your own.
3. `scripts/sim.sh all`, or open `KJTube/KJTube.xcodeproj` in Xcode and press Run.

`Secrets.xcconfig` is gitignored. Never commit a real key.

## What was left out

The Skip Ad feature's ad finder and its server, the tip jar's App Store setup, the upload and stats scripts, the website, and the private planning log. The Skip Ad button code is still in the player but switched off (`AppConfig.adFinder` returns nil).

## Playing by YouTube's rules

If you publish your version, read the [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service) and [Developer Policies](https://developers.google.com/youtube/terms/developer-policies). In short: play videos only in YouTube's official embedded player, don't cover or hide its controls, don't block ads, and show a privacy policy. `PUBLIC_BUILD = YES` in `App.xcconfig` is the flavour of this app that follows those rules; `NO` is the original personal flavour with custom controls, which is fine to study but not to publish.
