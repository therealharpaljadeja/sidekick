# Sidekick

A teleprompter that lives in your MacBook notch. Paste your script, hit **⌥⌘P**, and talk — Sidekick listens, drops the words you've said, and keeps the next ones right under the camera. It hides itself from screen recordings, screenshots and screen sharing, so your viewers never see it.

## Requirements

- macOS 13 Ventura or later (best on a MacBook with a notch; on other displays it hangs from the top centre of the screen)
- Xcode 15+ or the Swift 5.9+ command line tools

## Build and run

```bash
git clone https://github.com/therealharpaljadeja/sidekick.git
cd sidekick
./Scripts/build-app.sh --install   # builds build/Sidekick.app, copies it to /Applications, launches it
```

On first start, macOS asks for **Microphone** and **Speech Recognition** access. Sidekick has no Dock icon; it lives in the menu bar (speech bubble) and in the notch.

## Using it

1. Paste your script into the **Script** tab.
2. Click **Start in notch** (or press ⌥⌘P from anywhere).
3. Read. Spoken words disappear; the next word is white, the rest of the sentence light grey, later sentences darker.

| Shortcut | Action |
|---|---|
| ⌥⌘P | Start · pause · resume |
| ⌥⌘R | Restart from the top |
| ⌥⌘← / ⌥⌘→ | Previous / next sentence |
| ⌥⌘. | Stop and hide |

Click the notch to pause or resume; scroll over it to nudge word by word.

## Hiding from recordings

With **Settings → Hide from screen recordings** on (the default), every Sidekick window uses `NSWindow.sharingType = .none`. macOS leaves those windows out of screenshots, screen recordings and screen sharing while still drawing them on your display — no cropping. Turn the toggle off when you want Sidekick to appear in a demo.

Check it once with the recorder you actually use: a few capture tools on recent macOS versions capture the whole display buffer and may ignore this flag.

## How it follows you

Audio goes to Apple's Speech framework (on-device when supported, so nothing leaves your Mac). Each recognized word is matched against the next few script words with fuzzy matching, so filler words, small misrecognitions and dropped words don't derail it. Common words like "the" can't jump ahead on their own, and three matching words in a row can re-sync up to 40 words ahead if you skip a sentence.

The matching logic lives in `Sources/SidekickCore` and is covered by `swift test`.

## Credits

Type is [Intern](https://github.com/bvvst/intern), a rounded Inter by bvvst, under the SIL Open Font License (`Resources/Fonts/OFL.txt`).
