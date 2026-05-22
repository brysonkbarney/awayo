# Awayo

don't let your agents die.

Awayo is a tiny macOS menu bar app that keeps your Mac awake behind Awayo Lock.

It is built for the half-open laptop era: a CLI agent, build, download, test suite, or local service needs the Mac to stay awake, but leaving the desktop visible feels sketchy. Awayo Lock covers your displays with a passcode screen while agents, scripts, and long-running tasks keep going.

## What It Does

- Keep the Mac awake for 15 minutes, 30 minutes, 1 hour, 2 hours, or until stopped.
- Start Awayo Lock with a saved passcode, optional away note, and optional countdown.
- Pick from multiple Awayo Lock scenes and quiet patterns, including Duck Pond, Offline Runner, Screen Snapshot, and custom colors.
- Let visitors leave sticky notes on the Awayo Lock screen without unlocking the Mac, or turn notes off entirely.
- In Screen Snapshot mode, mouse movement can trigger a visible vintage NICE TRY camera countdown and Polaroid-style card.
- Start a native macOS Lock Screen while keeping background work awake.
- Run entirely from the menu bar.

**Awayo Lock** covers your screen; it is not the macOS Lock Screen. For full security, use **macOS Lock + Keep Awake**.

Awayo Lock creates an overlay on every connected display, keeps those overlays above normal and full-screen windows, and reasserts itself when macOS Spaces change. It also blocks common keyboard shortcuts and swipe/scroll gestures while Awayo Lock is active, while still allowing passcode entry.

The Awayo Lock passcode is set before starting a lock session. Awayo stores a salted local hash, not the passcode itself, so it does not need Keychain access.

The Screen Snapshot scene captures each display right before Awayo Lock appears and uses that image as the lock background with a tiny unlock control near the bottom. Move the pointer to the bottom edge to reveal the unlock control. macOS may ask for Screen Recording permission the first time this scene is used. Its NICE TRY gag shows a visible countdown before using the camera, and macOS may ask for Camera permission the first time.

Current Awayo Lock styles:

- Neon Flow
- Duck Pond
- Offline Runner
- Solar System
- Rainy Day
- Arcade Pulse
- Paper Notes
- Synthwave
- Custom Color
- Soft Wash
- Stripes
- Polka Dots
- Screen Snapshot

## Install

Run this on macOS:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/brysonkbarney/awayo/main/Scripts/install.sh)"
```

The installer downloads the latest release DMG, installs `Awayo.app` to `~/Applications/Awayo.app`, and opens it. If no release DMG exists yet, it falls back to building from source.

To install somewhere else:

```sh
AWAYO_INSTALL_DIR=/Applications /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/brysonkbarney/awayo/main/Scripts/install.sh)"
```

Installing to `/Applications` may require admin permissions. The default `~/Applications` install does not.

For now, the installer requires `git` and the Swift toolchain from Xcode Command Line Tools:

```sh
xcode-select --install
```

That requirement only applies to the source-build fallback.

## Run Locally

```sh
swift run Awayo
```

The app appears in the macOS menu bar. Quit it from the Awayo menu.

Open **Settings...** before your first Awayo Lock session to set the passcode and pick the look.

## Build the Mac App

```sh
Scripts/package_app.sh
Scripts/open_app.sh
```

The packaging script builds a release binary, creates `dist/Awayo.app`, and ad-hoc signs it for local testing.

To make a local DMG:

```sh
Scripts/package_dmg.sh
```

This creates `dist/Awayo-<version>.dmg` and `dist/Awayo.dmg`.

To install the packaged app into `~/Applications`:

```sh
Scripts/install.sh
```

To force a source build through the installer:

```sh
Scripts/install.sh --source
```

## Releases

Awayo uses semver tags and GitHub Releases.

1. Update `VERSION`.
2. Commit the version change.
3. Tag the commit, for example `git tag v0.1.0`.
4. Push the tag with `git push origin v0.1.0`.

The release workflow builds an unsigned/ad-hoc-signed DMG and uploads both `Awayo-<version>.dmg` and `Awayo.dmg`.

Unsigned DMGs work for early web distribution, but macOS may show an “unidentified developer” warning. Users can right-click Awayo and choose **Open**. A future Developer ID notarized build will remove that friction.

For a full launch smoke test:

```sh
Scripts/smoke_test.sh
```

To verify the keep-awake mechanism at the macOS power assertion level:

```sh
Scripts/verify_keep_awake.sh
```

## Roadmap

- Add themes, videos, and custom away cards.
- Add keyboard shortcuts.
- Add process-aware sessions, such as "keep awake while `npm test` is running."
- Add optional launch at login.

## Development

```sh
swift build
Scripts/package_app.sh
```

## License

MIT
