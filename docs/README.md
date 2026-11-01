# Selector

Tell the DJ what tonight is. Selector plans the whole night, explains it in a sentence, finds every song on Apple Music, and plays it: full songs for Apple Music subscribers, 30-second previews for everyone else. During the night you steer it like a real DJ: "more energy", "something we know", "wrap up in 20 minutes".

It runs in Safari or Chrome and installs to the iPhone home screen like an app.

## 1. Your Apple Music key (once, 10 minutes)

Selector talks to Apple Music with a developer token. You already have an Apple Developer account.

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources), open **Identifiers → + → Media IDs**. Description `Selector`, identifier like `media.com.yourname.selector`, tick **MusicKit**, register.
2. Open **Keys → +**, name it `Selector MusicKit`, tick **Media Services (MusicKit)**, choose the Media ID, then **Register** and **Download** the `.p8` file (one chance only). Note the **Key ID**. Your **Team ID** is under Membership.
3. In this folder, with Node 18+:

```
node make-token.mjs --team YOUR_TEAM_ID --key YOUR_KEY_ID --p8 ~/Downloads/AuthKey_YOUR_KEY_ID.p8 --origin http://localhost:3000
```

That writes `config.js`. Keep the `.p8` file private; it never goes on a website.

## 2. Run it

```
python3 -m http.server 3000
```

Open http://localhost:3000. Tap **Start the night**. You'll be offered **Connect Apple Music** (full songs, needs a subscription) or **Play previews** (30 seconds of every song, no sign-in).

## 3. Put it on your phone

1. Drag this folder onto https://app.netlify.com/drop (or deploy it with Vercel or GitHub Pages). You get an https address.
2. Make the token again with both addresses: `--origin http://localhost:3000,https://your-site.netlify.app`, and upload the new `config.js`.
3. On the iPhone, open the address in Safari → Share → **Add to Home Screen**. It opens full-screen with the Selector icon.

## How it works

- `app.js` holds the planner (a beam search scored by a transition model trained on 5,040 real DJ sets, plus the energy arc, tempo, sound balance, your taste and familiarity), the DJ's narration, Apple Music matching, two players (Apple Music full tracks, and a two-deck preview player that crossfades on desktop and Android), and live steering, which re-plans everything after the current song.
- `data.json` is the crate: 11,700 dance-ready songs with tempo, key and energy, the model, the learned club arc, and artist neighbours. Rebuild it with the Python pipeline from the earlier package.
- Everything personal (your taste, tonight's plan, past nights, Apple Music matches) stays in the browser's local storage.

## What to know

- **Previews blend; full songs don't.** Apple doesn't let web apps touch the audio of full tracks, so full songs play back to back. Save the night as a playlist and the Music app's AutoMix will blend it on iPhone.
- **On iPhone, keep Selector open** for full songs; Safari pauses web playback when the app is closed. Previews on iPhone play back to back without the blend (iOS doesn't allow volume fades on web audio from another site).
- **Catalog gaps.** Arabic and Persian songs are thin in the public data, so "Middle East" leans Turkish for now.
- **Apple's rules.** Listeners start playback themselves and can pause and skip. Don't charge for or advertise around Apple Music access itself.

## Files

`index.html` · `styles.css` · `app.js` · `data.json` · `config.js` (your token) · `make-token.mjs` · `manifest.webmanifest` · `sw.js` · icons
