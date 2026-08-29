# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project overview

**Vibe Stats for macOS** is a native menu bar app that monitors **Claude AI, GitHub Copilot, OpenAI and Google Gemini**, reporting **per-component** health rather than each vendor's global page indicator.

It is a pure-Swift reimplementation of the [Vibe Stats browser extension](https://github.com/todddube/vstat) (`~/Documents/Github/vstat`), which remains a separate product. The two share **one contract — the service registry** — and nothing else. There is no shared code.

- **This repo:** `https://github.com/todddube/vstat_mac`
- **Extension repo:** `https://github.com/todddube/vstat`

### The central design decision (non-negotiable)

**A service's indicator is rolled up from the components we watch — never from the vendor's page-level indicator.**

GitHub Issues going down must not make Copilot look broken. Conversely `Copilot: major_outage` under a calm page indicator must be reported as an outage. The page indicator is still captured as `pageIndicator` and shown as a divergence chip when the two disagree — that disagreement is the reason this app exists.

Two corollaries that keep getting re-derived, so they are stated once here:

- **An unmatched component is `unknown`, never `operational`.** Silently reporting a component we can no longer find as healthy is the failure mode the whole design guards against.
- **`unknown` is not on the severity scale.** `StatusIndicator.severity` returns `nil` for it, and `RollUp` carries an `unresolved` count alongside the verdict. The extension ranked `unknown` *below* `operational`, which is why a total API blackout renders there as "All dev tools are vibing!" — see [docs/REVIEW.md §3.1](docs/REVIEW.md). Do not reintroduce a rankable `unknown`.

## Commands

```bash
make generate   # project.yml -> VibeStats.xcodeproj (the project is GENERATED)
make build      # universal Debug build, ad-hoc signed WITH the sandbox live
make test       # 152 tests in 22 suites
make run        # build, kill any running copy, launch
make icon       # redraw the app icon at every size from Scripts/make-appicon.swift
make fixtures   # re-capture live vendor payloads into VibeStatsTests/Fixtures
make dmg        # package a DMG into dist/
make release    # Release archive
make notarize   # export, notarize, staple (needs a Developer ID + AC_PASSWORD profile)
make clean
```

`make` sets `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, so **no `xcode-select` is needed** — but any raw `xcodebuild` invocation must set it too.

## Architecture

Layers, top to bottom. **Dependencies point down only.** `Domain` imports nothing but `Foundation`.

```
App              main.swift · AppDelegate · StatusItemController
                 PopoverController · SettingsWindowController · AboutWindowController
Presentation     PopoverView · ServiceCardView · Settings/* · VibeIconRenderer · Palette
Coordination     MonitorCoordinator · NotificationDispatcher · SystemObservers
Engine           StatusEngine (actor) · StatuspageAdapter · GoogleCloudAdapter
Domain           StatusIndicator · RollUp · ServiceRegistry · Snapshot · StatusTransition
Infrastructure   StatusAPIClient · SnapshotStore · HistoryLog · Preferences · LaunchAtLogin
```

This mirrors the extension's own layering (`services.js` / `status-monitor.js` / `popup.js` / `background.js`) deliberately, so the parity matrix in [specs.md §3](specs.md) maps file to file.

### The file to edit first

`VibeStats/Domain/ServiceRegistry.swift` — every service, every component, every match pattern. Adding or changing a monitored component is a change to that file alone. **Registry order is significant**: it decides who claims a contested component via the `claimed` set in `ComponentMatcher`.

### Key invariants

| Where | Invariant |
|---|---|
| `StatusEngine.check` | `TaskGroup` ≙ `Promise.allSettled`: one service failing degrades *that* service to `unknown` and nothing else |
| `LiveStatusAPIClient` | Retry lives at the **request** level, not around the sweep. Transient (timeout/5xx/connection) only, never 4xx |
| `StatuspageAdapter` | Falls back to `pageIndicator` **only** when `resolvedCount == 0` |
| `IncidentPruner` | 10 most recent, within 14 days, newest first |
| `TransitionDiff` | Transitions into or out of `unknown` are never reported |
| `NotificationDispatcher` | First snapshot after launch is silent; ≥3 transitions in one service group into one notification; a burst is posted **worst-first** (Notification Centre stacks in arrival order) |
| `MonitorCoordinator.allows` | Offline suspends the scheduled sweep, but a **manual** refresh is always attempted — a Refresh button that does nothing is worse than one wasted request |
| `HistoryLog.pruneIfNeeded` | Prunes at launch **and** at most once a day thereafter; a machine that never restarts is the one whose log would otherwise grow |
| `PopoverSession` | Countdown is **deadline-driven**, not decrement-per-tick |

## Conventions

- **Swift 6 language mode**, `SWIFT_STRICT_CONCURRENCY=complete`. Default isolation stays `nonisolated`; UI annotates itself (see [docs/ARCHITECTURE.md §2.1](docs/ARCHITECTURE.md) for why not `-default-isolation MainActor`).
- **Never hand-edit `VibeStats.xcodeproj`** — it is generated from `project.yml` and gitignored.
- **No third-party runtime dependencies.** SwiftUI + AppKit + Foundation + UserNotifications + ServiceManagement + Network only.
- **No view names a hex value.** Colours come from `Palette` semantic tokens.
- **Status is never carried by colour alone** — always colour *and* text, and `unknown` gets a distinct hollow shape so it survives monochrome and colour-blindness.
- **Comments explain why, not what.** Several comments record a bug that was actually hit; leave those in place.

## Environment gotchas

These all cost real time to discover. Read before debugging something that "should work".

**This checkout lives in `~/Documents`, which iCloud Drive syncs.**
- DerivedData is deliberately **outside the repo** (`~/Library/Developer/Xcode/DerivedData/VibeStats-build`). In-tree, iCloud stamps `com.apple.FinderInfo` on directories and codesign fails with *"resource fork, Finder information, or similar detritus not allowed"*.
- iCloud creates conflict copies like `VibeStats 2.xcodeproj` when XcodeGen rewrites the project mid-sync. `make generate` deletes them first. They are always stale and always safe to delete.

**Debug builds are ad-hoc signed with the sandbox LIVE**, not unsigned. Building unsigned hides container-path and entitlement problems until release day.

**Do not use a SwiftUI `Settings` scene.** Opening it requires sending `showSettingsWindow:`, a selector SwiftUI installs but does not expose or document, and for an accessory (`LSUIElement`) app it silently does nothing. The app uses a plain AppKit `main.swift` and owns its windows via `SettingsWindowController` / `AboutWindowController`.

**`NSApp.occlusionState` reflects the app's *windows*.** A menu-bar-only app has none, so gating the icon animation on it freezes the glyph permanently. Display sleep is handled with explicit `NSWorkspace.screensDidSleep/Wake` observers instead.

**"Invalid view geometry: width is negative" on the first Settings open is not ours.** AppKit logs it four times — once per tab — from inside SwiftUI's `TabView` during its first layout pass only. It is not reproduced by reusing the window, and it is unaffected by `scenePadding()`, by the window's content size, or by pre-sizing the hosting view. `WindowTests.settingsContentFits` guards the thing that *was* ours (content wider than its window); do not go chasing the log again.

**`OSLog` is not queryable here.** `log show --predicate 'subsystem == "com.todddube.VibeStats"'` returns nothing for the sandboxed process. Verify behaviour with tests, not log-grepping.

**Screenshotting the running app is unreliable.** An accessory app launched from a background shell cannot take focus, so the popover ends up behind other windows. Use the offscreen rendering techniques below instead. `VIBESTATS_OPEN_POPOVER=1` and `VIBESTATS_OPEN_SETTINGS=1` (DEBUG only) open those surfaces at launch if you do want to try.

## Testing

`make test` — 152 tests, 22 suites, Swift Testing (`import Testing`, not XCTest).

**The test host is the sandboxed app itself.** Consequences:

- **Fixtures travel inside the test bundle** (`project.yml` copies `VibeStatsTests/Fixtures` as a resource). They cannot be read from the source tree by path.
- Recorded live payloads from all four vendors drive `EngineTests`; `Fixture.mutated(_:_:)` edits decoded JSON in-memory to build the "vendor changed something" variants rather than checking in a dozen near-identical files.

**Rendering views for visual review:**

- `ImageRenderer` lays out a `ScrollView` or a `Form` to **nothing** — anything inside one is invisible. That is why `PopoverContentView` is extracted from `PopoverView`.
- For `Form`-based views (all the settings tabs), render through a real `NSHostingView` in an offscreen `NSWindow` and `cacheDisplay(in:to:)`. See `SettingsSnapshotTests`.
- Snapshots land in the test host's container tmp: `~/Library/Containers/com.todddube.VibeStats/Data/tmp/`. The test prints the path.
- Menu bar glyph contact sheets are rendered per appearance, because a template image drawn in the label colour is meaningless outside the appearance it was rendered for.

**NSPopover in tests** is fragile. Use a `.titled` anchor window (a `.borderless` one returns `NO` from `canBecomeKeyWindow`), inject `behavior: .applicationDefined` to isolate our auto-close from AppKit's transient dismissal, and **close the popover and yield before closing the anchor window** — closing it out from under a live popover takes the process down.

## Implementation status

All eight planned phases are complete: the app builds universal in Debug and Release, is signed with a live sandbox, monitors all four services against the real APIs, and ships a menu bar glyph, popover, settings, notifications, an app icon and a DMG.

### Known gaps / next steps

| Item | Note |
|---|---|
| **Icon Composer `.icon`** | macOS 26's layered icon format cannot be authored from a script. The classic asset catalogue ships and works; converting is a manual Icon Composer pass over the layers described in [docs/ICONS.md §4](docs/ICONS.md) |
| **Global hotkey** | Specced ([specs.md §5.2](specs.md)) but not implemented and not exposed in Settings. Nothing is dead-ended |
| **Card reordering** | Specced, not implemented — cards render in registry order |
| **Per-service component visibility** | The Services settings tab lists components read-only; the spec allows choosing which appear on a card |
| **Localisation** | All strings go through `String(localized:)` but only `en` ships |
| **Notarization** | `make notarize` exists but has never been run — needs a Developer ID and an `AC_PASSWORD` keychain profile |

### Two fixes worth back-porting to the extension

Independent of this repo, and both user-visible:

1. `rollUpStatus` returning `operational` for an all-unknown input, which renders a total API blackout as "All dev tools are vibing!" ([docs/REVIEW.md §3.1](docs/REVIEW.md))
2. Retry logic that `Promise.allSettled` renders unreachable ([docs/REVIEW.md §3.2](docs/REVIEW.md))

## Documentation map

| Document | Contents |
|---|---|
| [specs.md](specs.md) | Product spec, the extension→macOS parity matrix, the full service registry, FRs and NFRs |
| [docs/REVIEW.md](docs/REVIEW.md) | Review of the browser extension, including the two defects above |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layering, types, concurrency contract, persistence, error taxonomy |
| [docs/DESIGN.md](docs/DESIGN.md) | Colour and type tokens, layout, the 13-entry animation catalogue, accessibility |
| [docs/ICONS.md](docs/ICONS.md) | The four-spoke menu bar mark, every glyph state, the six-spoke app icon |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones, test plan, release plan, post-1.0 ideas |
