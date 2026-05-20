# Awayo

don't let your agents die.

Awayo is a tiny macOS menu bar app that keeps your Mac awake behind Awayo Lock.

It is built for the half-open laptop era: a CLI agent, build, download, test suite, or local service needs the Mac to stay awake, but leaving the desktop visible feels sketchy. Awayo Lock covers your displays with a passcode screen while agents, scripts, and long-running tasks keep going.

## What It Does

- Keep the Mac awake for 15 minutes, 30 minutes, 1 hour, 2 hours, or until stopped.
- Start Awayo Lock with a saved passcode, away note, and countdown.
- Pick from multiple Awayo Lock scenes and quiet patterns, including Duck Pond, Offline Runner, and custom colors.
- Let visitors leave sticky notes on the Awayo Lock screen without unlocking the Mac.
- Start a native macOS Lock Screen while keeping background work awake.
- Run entirely from the menu bar.

**Awayo Lock** covers your screen; it is not the macOS Lock Screen. For full security, use **macOS Lock + Keep Awake**.

Awayo Lock creates an overlay on every connected display, keeps those overlays above normal and full-screen windows, and reasserts itself when macOS Spaces change. It also blocks common keyboard shortcuts and swipe/scroll gestures while Awayo Lock is active, while still allowing passcode entry.

The Awayo Lock passcode is set before starting a lock session. Awayo stores a salted local hash, not the passcode itself, so it does not need Keychain access.

Current Awayo Lock styles:

- Neon Flow
- Duck Pond
- Offline Runner
- Cosmic Desk
- Rainy Window
- Arcade Pulse
- Paper Notes
- Synthwave
- Custom Color
- Soft Wash
- Stripes
- Polka Dots

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
