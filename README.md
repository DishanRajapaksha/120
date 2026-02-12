# OneTwenty (macOS 120Hz Nudge App)

OneTwenty is a small native menu bar app that keeps display composition active by flipping a 1x1 near-transparent pixel using `CVDisplayLink`. This can help macOS stay at high refresh rates in low-motion scenarios.

## Runtime reliability features

- Lifecycle handling for sleep/wake and screen topology changes.
- Watchdog that detects stale display ticks and requests bounded restarts.
- Start retry backoff for `CVDisplayLink` failures.
- Launch at Login with `SMAppService` primary path and LaunchAgent fallback.
- Local-only diagnostics logging (no network telemetry).

## Requirements

- macOS 13+
- Xcode Command Line Tools + SwiftPM

## Build and run

```zsh
make build
make run
```

The app starts as a menu bar accessory (`LSUIElement`) with:
- `Turn On` / `Turn Off`
- `Launch at Login`
- `Quit OneTwenty`

## Tests

```zsh
make test
```

Current test coverage includes:
- Display target selection fallback behavior
- Watchdog stale/throttle policy logic
- Launch-at-login strategy selection and fallback behavior

## Diagnostics

- Unified logging category: `com.example.onetwenty` (or app bundle identifier if customized)
- Local log file: `~/Library/Logs/OneTwenty/onetwenty.log`
- Rotation: 512KB with one backup file (`onetwenty.log.1`)

## Release packaging

```zsh
make app
make zip
make release-check
```

- App bundle is generated at `dist/OneTwenty.app`
- ZIP package is generated at `dist/OneTwenty-1.0.0.zip` (override with `VERSION=...`)

Notarization is scaffolded but intentionally not configured yet:

```zsh
make notarize
```

## Manual runtime validation checklist

1. Toggle nudging on/off repeatedly from the menu bar icon.
2. Put the Mac to sleep, wake it, and verify nudging resumes within 3 seconds.
3. Attach/detach external monitors and verify nudging continues.
4. Enter/exit full-screen spaces and verify no visible artifact from the 1x1 nudge window.
5. Verify idle CPU remains at or below the target budget over a 10-minute run.

## Caveats

- This is still best-effort behavior; macOS may downshift refresh rate based on system heuristics, battery/power mode, or display limitations.
- Launch at Login behavior can vary depending on whether the app is running from an unsigned dev location vs. a bundled app in a standard install path.

## Uninstall

Quit the app, remove the binary/app bundle, and optionally delete:
- `~/Library/Logs/OneTwenty`
- `~/Library/LaunchAgents/<bundle-id>.agent.plist` (if LaunchAgent fallback had been enabled)
