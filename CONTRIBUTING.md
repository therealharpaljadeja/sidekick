# Contributing

Bug reports, ideas and pull requests are welcome. For anything bigger than a small fix, open an issue first so we can agree on the approach.

## Develop

You need macOS 13+ and Xcode 15+.

```bash
swift test                          # SidekickCore unit tests
./Scripts/build-app.sh --install    # build, copy to /Applications and launch
```

Keep the look as it is: black, white and grey only, the bundled Intern font, 4 px corners and hairline borders.

## Pull requests

- Branch from `main`; `main` is protected, so every change goes through a PR.
- CI runs `swift test` and a universal app build on every PR.
- Add user-facing changes under **Unreleased** in [`CHANGELOG.md`](CHANGELOG.md).

## Releasing

1. In a PR, move the **Unreleased** notes in `CHANGELOG.md` under a new version heading, and bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist`.
2. After it merges, tag `main` with the same version:
   ```bash
   git checkout main && git pull
   git tag v0.2.0 && git push origin v0.2.0
   ```
3. The [Release workflow](.github/workflows/release.yml) tests, builds the universal DMG, and publishes a GitHub Release with the changelog notes, the DMG and its SHA-256.

The workflow signs and notarizes the DMG when these repository secrets are set; without them it publishes an unsigned build:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE` | Base64 of your "Developer ID Application" `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | The `.p12` export password |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | Your 10-character team ID |
| `APPLE_APP_PASSWORD` | An [app-specific password](https://account.apple.com) for notarization |
