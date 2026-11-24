# Changelog

All notable changes to Sidekick are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- With Apple Intelligence on, a checklist item ticks off only once you say you're done with it or start a later one, not as soon as you start talking about it. If you've already covered the next item too, both tick off.

### Added

- Clear warning in the Checklist tab, and **Key words only** in the notch, when Apple Intelligence isn't available.
- Debug logging of each Apple Intelligence decision.

## [0.2.1] - 2026-11-24

### Changed

- New app icon.

## [0.2.0] - 2026-11-23

### Added

- **Checklist mode**: type one talking point per line and the notch shows the current item and the next ones. Sidekick ticks an item off when it hears you cover it, even in your own words.
  - With Apple Intelligence on (macOS 26, supported Mac), the on-device model judges whether you've covered an item. Otherwise Sidekick matches the item's key words, allowing other word forms.
  - ⌥⌘→ ticks off the current item by hand, and ⌥⌘← brings the last one back.
- ⌥⌘P starts whichever tab is open, Script or Checklist.

## [0.1.0] - 2026-11-22

First public release.

### Added

- Teleprompter in the MacBook notch that listens with Apple Speech and follows your script as you read it, including after pauses.
- Credits-style roll: the next six words are white, the rest grey, and the script rolls up a line at a time with a faded peek of what's next.
- **Hide from screen recordings** toggle, an editable global shortcut for it (default ⌃⌥⌘H) and a light in the notch showing whether Sidekick is hidden.
- Global shortcuts to start, pause, restart, skip sentences and stop.
- Settings for text size, panel width, number of lines and speech language.
- Dock icon that reopens the main window.
- Universal (Apple Silicon + Intel) DMG.

[Unreleased]: https://github.com/therealharpaljadeja/sidekick/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/therealharpaljadeja/sidekick/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/therealharpaljadeja/sidekick/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/therealharpaljadeja/sidekick/releases/tag/v0.1.0
