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

## Agent Status Hooks

Awayo Lock shows an **agents alive** panel in the top-left corner. It passively detects obvious agent processes like Codex and Claude Code, then shows a safe hint such as the worktree folder or short session id.

When available, Awayo enriches those safe hints with local app metadata:

- Claude Code: maps running `--resume` session ids to local Claude Code titles, cwd, and worktree names.
- Codex: reads local Codex session titles, cwd, recent activity, and open child-session counts without reading transcript bodies or tool output.

For better status, scripts and agent wrappers can write a tiny local hook:

```sh
swift Scripts/awayo_agent_status.swift upsert \
  --id codex-awayo \
  --name Codex \
  --detail "Awayo lock polish" \
  --state working
```

Supported states are `working`, `ready`, `waiting`, `quiet`, and `alive`. `ready` appears as `needs you` on the lock screen.

Clear a hooked session when it is done:

```sh
swift Scripts/awayo_agent_status.swift clear --id codex-awayo
```

Hooks are stored at `~/Library/Application Support/Awayo/agent-sessions.json` and expire automatically if they stop updating.

## Roadmap

- Add themes, videos, and custom away cards.
- Add first-class integrations for more agent providers and richer ready-for-input state.
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
