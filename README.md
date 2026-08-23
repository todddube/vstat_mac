# Vibe Stats for macOS

A native menu bar app that monitors **Claude AI, GitHub Copilot, OpenAI and Google Gemini**, reporting **per-component** health rather than each vendor's global page indicator.

A pure-Swift reimplementation of the [Vibe Stats browser extension](https://github.com/todddube/vstat), with the things a native app can do that an extension cannot: a status-bearing menu bar glyph, transition notifications, uptime history, and sleep/wake awareness.

> GitHub Issues going down must not make Copilot look broken. Conversely `Copilot: major_outage` under a calm page indicator must be reported as an outage. The page indicator is kept alongside, purely to show where the two disagree — that disagreement is the reason this app exists.

## Requirements

macOS 26.0+ · Xcode 27 · Swift 6 language mode

## Build

The Xcode project is **generated** from `project.yml`. Never hand-edit the `.xcodeproj` — regenerate it.

```bash
make generate   # project.yml -> VibeStats.xcodeproj
make build      # universal Debug build, ad-hoc signed WITH the sandbox live
make test       # unit tests
make run        # build, kill any running copy, launch
make fixtures   # re-capture live vendor payloads into VibeStatsTests/Fixtures
make release    # Release archive
make icon       # redraw the app icon at every size
make dmg        # package a DMG into dist/
make notarize   # export, notarize and staple (needs a Developer ID)
```

`make` sets `DEVELOPER_DIR`, so no `xcode-select` is needed. DerivedData is deliberately kept outside the repo — see docs/ARCHITECTURE.md §2.

## Status

| Phase | State |
|---|---|
| 0 — Xcode project scaffolding | ✅ |
| 1 — Domain layer | ✅ |
| 2 — Engine, adapters, fixtures | ✅ |
| 3 — Coordination and persistence | ✅ |
| 4 — Menu bar glyph | ✅ |
| 5 — Popover UI | ✅ |
| 6a — Settings panel (General · Services · Appearance) | ✅ |
| 6b — Transition notifications | ✅ |
| 7 — App icon, About window, DMG | ✅ |

126 tests in 19 suites. Debug and Release both build clean, universal (arm64 + x86_64). Known gaps are listed in [CLAUDE.md](CLAUDE.md#known-gaps--next-steps).

## Resuming work

Read [CLAUDE.md](CLAUDE.md) first. It carries the commands, the invariants that must not be re-broken, the environment gotchas that cost real time to discover, and the list of known gaps.

## Documentation

| Document | Contents |
|---|---|
| [specs.md](specs.md) | Product and functional specification, parity matrix, the service registry |
| [docs/REVIEW.md](docs/REVIEW.md) | Review of the browser extension, including two defects worth back-porting |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layering, types, concurrency, persistence, error taxonomy |
| [docs/DESIGN.md](docs/DESIGN.md) | Visual system, layout, the animation catalogue, accessibility |
| [docs/ICONS.md](docs/ICONS.md) | The four-spoke hub mark, every glyph state, the app icon |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones, test plan, release plan |
| [CLAUDE.md](CLAUDE.md) | Working notes: commands, invariants, environment gotchas, status |

## Privacy

Requests go to exactly four hosts — the vendors' own status endpoints. No accounts, no telemetry, no analytics, no identifiers. All state is local, in the app's sandbox container.
