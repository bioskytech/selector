# Selector for iPhone

The native app. Same DJ as the web app, same design, plus the two things a browser can't do: full Apple Music songs that blend into each other (iOS 18), and music that keeps playing with the phone in your pocket.

Tell it what tonight is, it plans the night and explains it in a sentence, finds every song on Apple Music, and plays it. Steer it while it plays: "more energy", "something we know", "wrap up in 20 minutes". Previews (30 seconds, blended) for anyone; full songs for Apple Music subscribers.

## What you need

- A Mac with **Xcode 16 or later**.
- An **iPhone on iOS 17 or later**. Blended full songs need **iOS 18**. The Simulator can't play Apple Music; previews work there.
- Your **Apple Developer account**.

## Run it on your phone (about 15 minutes)

### 1. Turn on MusicKit for a bundle ID

1. Open [Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list), click **+**, choose **App IDs → App**.
2. Description `Selector`, Bundle ID **Explicit**, for example `com.yourname.selector`.
3. Under **App Services** tick **MusicKit**. Register.

That's all the Apple Music setup: on iOS, MusicKit makes the developer token itself from your Team ID and bundle ID. (If you ran the app before doing this, find the App ID Xcode created and tick MusicKit there, then wait a few minutes.)

### 2. Open and sign

1. Open `Selector.xcodeproj`.
2. Target **Selector → Signing & Capabilities**: choose your **Team**, set the **Bundle Identifier** from step 1.

### 3. Run

Plug in the phone, choose it as the destination, press **Run**. First time: on the phone, **Settings → General → VPN & Device Management**, trust your certificate, open the app again. Allow Apple Music access when asked.

The first plan takes 10–20 seconds to find its songs on Apple Music (two searches per song). Matches are remembered.

## TestFlight, for friends

**Product → Archive**, then **Distribute App → TestFlight & App Store**. In App Store Connect, add testers under TestFlight. Testers without an Apple Music subscription get previews; the app offers them Apple's own subscription sheet, which is how Apple wants it done.

## How it's built

| Where | What |
|---|---|
| `Models/Planner.swift` | The planner: beam search scored by the transition model trained on 5,040 real DJ sets, the energy arc, tempo, sound balance, taste and familiarity. Re-plans the rest of the night for live steering. Phases, and the DJ's narration. |
| `Models/Catalog.swift`, `Resources/app_data.json` | The crate: 11,700 songs with tempo, key and energy; the model; the learned club arc; artist neighbours. Rebuilt by the Python pipeline. |
| `Models/Night.swift` | The night as it plays: plan, Apple Music matches, what played, what you loved, requests. Settings and recaps that persist. |
| `Services/AppleMusicMatcher.swift` | Finds each song on Apple Music by title, artist and length. |
| `Services/Player.swift` | Full songs through `ApplicationMusicPlayer` with `.crossfade` on iOS 18; previews through two `AVPlayer`s that fade into each other. |
| `AppState.swift` | Everything the screens talk to: planning, steering, Apple Music, the recap, the playlist. |
| `Views/` | Tonight, Brief, Plan, Songs, Playing, the steer and connect sheets, Recap, the mini player. |

## If something goes wrong

| What you see | Likely cause | Fix |
|---|---|---|
| "Couldn't start playback" mentioning a token or MusicKit | MusicKit isn't on for this bundle ID, or the bundle ID in Xcode differs from the App ID | Step 1, wait a few minutes, run again |
| Previews but you have a subscription | The Apple ID on the phone isn't the subscribed one | Sign in with it in Settings |
| Songs play back to back with no blend | iOS 17 | iOS 18 blends full songs; previews blend on any version |
| Build error on a MusicKit symbol | Older Xcode | Xcode 16 or later |
| "Allow Apple Music access" | Access was declined | Settings → Privacy & Security → Media & Apple Music → Selector |
