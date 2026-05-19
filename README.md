# Awayo

Awayo is a tiny macOS menu bar app for stepping away while your work keeps running.

It is built for the familiar developer problem: a CLI agent, build, download, test suite, or local service needs the Mac to stay awake, but leaving the desktop visible feels sketchy.

## What It Does

- Keep the Mac awake for 15 minutes, 30 minutes, 1 hour, 2 hours, or until stopped.
- Start Awayo Lock with an away note, countdown, and passcode.
- Start a native macOS Lock Screen while keeping background work awake.
- Run entirely from the menu bar.

**Awayo Lock** is intentionally a casual lock screen, not a replacement for the macOS Lock Screen. For real security, use **macOS Lock + Keep Awake**.

## Run Locally

```sh
swift run Awayo
```

The app appears in the macOS menu bar. Quit it from the Awayo menu.

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

## Roadmap

- Add a better first-run onboarding flow.
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
