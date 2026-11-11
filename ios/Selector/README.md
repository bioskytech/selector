# Selector for iPhone

Tell it what tonight is, in taps or in a sentence. It plans the night, explains it, and plays it. While it plays you can ask for a song, an artist, a sound or a mood, and it re-plans around what's on.

It plays out of the box: with nothing set up it finds every song through Apple's public lookup and plays 30-second previews, blended. Connect Apple Music with a subscription and the same night plays as full songs, with blends timed to each transition (iOS 18).

## What you need

- A Mac with **Xcode 16 or later**.
- An **iPhone on iOS 17 or later**. Blended full songs need **iOS 18**; the on-device language model needs **iOS 26**. The Simulator can't play Apple Music; previews work there.
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
| `Models/Planner.swift` | The planner: beam search scored by the transition model trained on 5,040 real DJ sets, the energy arc, tempo, sound balance, taste and familiarity. Headliners own the peak. Re-plans the rest of the night for live requests. Phases, blend lengths, and the DJ's narration. |
| `Models/Requests.swift` | Understands requests and typed briefs: sounds, artists, song titles, energy, time, and descriptions of the room ("everyone's sitting down"). |
| `Services/OnDeviceDJ.swift` | When a request is phrased in a way the parser doesn't know, asks the model built into the iPhone (iOS 26, Apple Intelligence). Nothing leaves the phone. |
| `Models/Catalog.swift`, `Resources/app_data.json` | The crate: 11,700 songs with tempo, key and energy; the model; the learned club arc; artist neighbours. |
| `Models/Night.swift`, `Models/Track.swift` | The night as it plays: plan, found songs, what played, what you loved, requests. |
| `Services/AppleMusicMatcher.swift`, `Services/ITunesMatcher.swift` | Find each song on Apple Music, or through the public lookup when Apple Music isn't connected. |
| `Services/Player.swift` | Full songs through `ApplicationMusicPlayer`; previews through two `AVPlayer`s that fade into each other. |
| `AppState.swift` | Everything the screens talk to. |
| `Views/` | Tonight, Brief, Plan, Songs, Playing, the sheets, Recap. `Theme.swift` holds the look: Anton for poster titles (SIL Open Font License, in `Resources/Fonts`), and an accent colour that follows tonight's lead sound. |
| `Tests/main.swift` | A command-line check, run on every push, that prints what the DJ understands and plans. |

Every push is built on a Mac in GitHub Actions, run in the Simulator, and screenshotted into the `screenshots` branch.

## If something goes wrong

| What you see | Likely cause | Fix |
|---|---|---|
| Previews only, and the Apple Music sheet says it "isn't answering for this build" | MusicKit isn't on for this bundle ID, or the bundle ID in Xcode differs from the App ID | Step 1, wait a few minutes, run again |
| Previews but you have a subscription | The Apple ID on the phone isn't the subscribed one | Sign in with it in Settings |
| Songs play back to back with no blend | iOS 17 | iOS 18 blends full songs; previews blend on any version |
| Build error on a MusicKit symbol | Older Xcode | Xcode 16 or later |
| "Allow Apple Music access" | Access was declined | Settings → Privacy & Security → Media & Apple Music → Selector |
