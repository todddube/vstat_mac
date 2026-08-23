# Vibe Stats for macOS — Product & Functional Specification

**Document status:** v1.1 — implemented (2026-08-23)
**Implementation status:** all eight phases built; see [CLAUDE.md](CLAUDE.md) for what is done, what is not, and where to pick up.
**Owner:** Todd Dube
**Source of truth for behaviour parity:** `~/Documents/Github/vstat` (Vibe Stats browser extension v1.3.1)

| Companion document | Purpose |
|---|---|
| [docs/REVIEW.md](docs/REVIEW.md) | Review of the existing extension: what it does, what is good, what is broken or missing, what must change on macOS |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Swift module layout, types, concurrency model, persistence, scheduling, error handling |
| [docs/DESIGN.md](docs/DESIGN.md) | Visual system, popover layout, settings UI, animation catalogue, accessibility |
| [docs/ICONS.md](docs/ICONS.md) | Menu bar icon and app icon design, including drawing code and every state |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones, work breakdown, test plan, release/notarization plan |
| [CLAUDE.md](CLAUDE.md) | **Start here to resume work.** Commands, invariants, environment gotchas, current status and known gaps |

---

## 1. Summary

**Vibe Stats** is a macOS menu bar app that continuously monitors the health of AI developer tools — **Claude AI, GitHub Copilot, OpenAI, and Google Gemini** — and reports **per-component** status rather than each vendor's global page indicator.

It is a native, pure-Swift reimplementation of the Vibe Stats browser extension. It reproduces the extension's monitoring semantics exactly (same registry, same status mapping, same roll-up rule), and then does the things a native app can do that an extension cannot: live in the menu bar with an animated status glyph, notify on transitions, keep uptime history, survive sleep/wake, and launch at login.

### 1.1 Product one-liner

> The health of every AI tool you code with, in your menu bar — component-accurate, not vendor-marketing-accurate.

### 1.2 Non-goals

- No account, no login, no telemetry, no analytics, no network traffic to anything but the four vendor status endpoints.
- Not a general-purpose uptime monitor. The service registry is curated, not user-extensible in v1.0 (see §7.4 for the v1.1 escape hatch).
- No iOS/iPadOS target in v1.0.
- Does not replace or bundle the browser extension; the two are independent products sharing a design language.

---

## 2. The central design decision (inherited, non-negotiable)

**A service's indicator is rolled up from the components we watch — never from the vendor's page-level indicator.**

GitHub Issues going down must not make Copilot look broken. Conversely, `Copilot: major_outage` sitting under a page-level `major` must be reported as **critical**. The page indicator is still captured as `pageIndicator` and surfaced in a tooltip/disclosure when the two disagree — that disagreement is the product's whole reason to exist.

The page indicator is used as the service indicator **only** when zero components could be resolved (i.e. the vendor changed their API shape).

An unmatched component reports `unknown` — **never** `operational`. Silently reporting a missing component as healthy is the failure mode this design guards against.

---

## 3. Functional parity matrix

Every behaviour of the extension, and its macOS disposition. `PARITY` = must behave identically. `ADAPT` = same intent, native mechanism. `NEW` = native-only capability. `DROP` = does not apply.

### 3.1 `src/core/services.js` — registry & mapping

| Extension symbol | macOS | Swift home |
|---|---|---|
| `SERVICE_IDS`, `SERVICES` | PARITY | `ServiceRegistry.swift` — static `let services: [ServiceDefinition]`, identical ids, names, vendors, URLs, components, `primary` flags |
| `GOOGLE_AI_KEYWORDS` | PARITY | `ServiceRegistry.googleAIKeywords` |
| `COMPONENT_STATUS_MAP` | PARITY | `StatusIndicator.init(componentStatus:)` |
| `STATUS_PRIORITY`, `statusRank`, `worstStatus`, `rollUpStatus` | PARITY | `StatusIndicator: Comparable` + `rollUp(_:)`; `unknown(0) < operational(1) < minor(2) < major(3) < critical(4)` |
| `mapComponentStatus` incl. keyword-sniffing fallback | PARITY | `StatusIndicator.init(componentStatus:)` — exact map, then `contains` sniffing in the same order |
| `mapPageIndicator` | PARITY | `StatusIndicator.init(pageIndicator:)` |
| `matchComponent` (exact `match` → regex `patterns`, with `claimed` set) | PARITY | `ComponentMatcher.match(_:in:claimed:)`; regexes as `NSRegularExpression` compiled once, statically |
| `statusLabel`, `componentStatusText` | PARITY | `StatusIndicator.title` / `.compactTitle` |

### 3.2 `src/core/status-monitor.js` — `VStateMonitor`

| Extension method | macOS | Notes |
|---|---|---|
| `init()` | ADAPT | `MonitorCoordinator.start()` — installs the repeating timer, does an immediate check |
| `checkAllStatuses(retryCount)` | PARITY | `TaskGroup` over services ≙ `Promise.allSettled`; one failure degrades that service to `unknown` only. Same retry policy: up to 3 retries, linear backoff `2s × (attempt+1)` |
| `checkService` dispatch | PARITY | `switch definition.api` over `enum ServiceAPI { case statuspage(base:), googleCloud(incidentsURL:) }` |
| `checkStatuspageService` | PARITY | Three parallel GETs (`status.json`, `components.json`, `incidents.json`), each independently failable |
| `resolveComponents` | PARITY | Preserves the `claimed` set semantics exactly |
| `normalizeStatuspageIncident` + `affectsWatched` | PARITY | |
| `checkGoogleCloudService` | PARITY | Keyword filter over the flat feed; synthetic component states derived from *active* incidents |
| `incidentText`, `normalizeGoogleIncident`, `mapGoogleStatus`, `mapGoogleSeverity`, `googleImpactToIndicator` | PARITY | `searchText` stays internal and is never persisted (same as today) |
| `combineStatuses`, `describeCombined` | PARITY | Including the copy: `"All dev tools are vibing!"` |
| `unknownService` | PARITY | |
| `persist` | ADAPT | JSON snapshot to Application Support instead of `chrome.storage.local`. **The legacy per-service duplicate keys (`<id>Status`/`<id>Incidents`/`<id>Components`) are dropped** — they exist only for old-popup back-compat |
| `pruneIncidents` (max 10, max 14 days) | PARITY | |
| `handleCheckFailure` | PARITY | |
| `updateBadgeIcon` / `badgeColor` | ADAPT | Becomes the menu bar item: glyph state, optional count badge, tooltip. See [ICONS.md](docs/ICONS.md) |
| `fetchJson` (10 s timeout, `no-cache`, `Accept: application/json`) | PARITY | `URLSession` with `timeoutIntervalForRequest = 10`, `.reloadIgnoringLocalCacheData` |
| `formatIncidentTitle` | ADAPT | `Date.FormatStyle`, locale-aware (extension hardcoded `en-US`) |

### 3.3 `src/popup/` — `VStatePopupController`

| Extension behaviour | macOS |
|---|---|
| Pure renderer, never calls an API itself | PARITY — the popover reads the store; only the coordinator fetches |
| Overall status banner + description + affected-component tooltip | PARITY |
| 2×2 service card grid, per-service badge, primary component rows | PARITY (redesigned visually — see [DESIGN.md](docs/DESIGN.md)) |
| Badge tooltip showing watched-components vs whole-page disagreement | PARITY, promoted to a visible inline chip |
| Card subtitle flips to naming degraded components | PARITY |
| Click a card → open vendor status page | PARITY (`NSWorkspace.shared.open`) |
| "View Issues" disclosure, incidents sorted `affectsWatched` first, top 5 | PARITY |
| Auto-refresh of the *view* every 120 s; stale-check (>30 s) on visibility | ADAPT — the store is observable, so the view updates on change; a stale check runs on popover open |
| Manual refresh button, ⌃R / F5 | ADAPT — ⌘R, and a refresh affordance in the popover header |
| About modal | ADAPT — a native About window that also carries the repository, the browser-extension repo, and the privacy policy, so the popover menu needs one item instead of four |
| Escape closes modal | PARITY |
| No `innerHTML`, all `textContent` (vendor text can never be markup) | PARITY by construction — SwiftUI `Text` never interprets markup from these fields |

### 3.4 `src/background.js` + `src/platform/browser-shim.js`

| Extension concern | macOS |
|---|---|
| MV3 service worker termination, `getMonitor()` rebuild-on-demand, cold-start alarm guarantee | DROP — a native app has a stable process. `MonitorCoordinator` is a long-lived singleton |
| `chrome.alarms` 5-min period | ADAPT — `DispatchSourceTimer`, user-configurable interval (§5.2) |
| `runtime.onMessage` `forceRefresh` / `getStatus` | DROP — direct method calls |
| `browser-shim.js` in its entirety | DROP — there is one platform |
| Safari module-graph flattening, bundle-id nesting constraints | DROP |

### 3.5 Native-only additions

| Capability | Rationale |
|---|---|
| Menu bar glyph with live status colour + animation | The whole point of a menu bar app |
| **Notifications on status transitions** | The extension could not do this reliably under MV3; it is the highest-value native win |
| **Uptime history + sparkline** (rolling 7 days of samples) | Cheap to keep natively, answers "was it just me?" |
| **Launch at login** (`SMAppService`) | |
| **Sleep/wake + network-change awareness** | Refresh on wake and on regaining connectivity instead of waiting out the interval |
| **Settings window** | Interval, per-service enable, notification rules, appearance, motion |
| **Global hotkey** to toggle the popover | |
| **Menu bar title text mode** (optional compact text next to the glyph) | |

---

## 4. Monitored services (registry, verbatim from the extension)

Priority scale: `critical(4) > major(3) > minor(2) > operational(1) > unknown(0)`

Statuspage component status → indicator:

| Statuspage | Indicator |
|---|---|
| `operational` | operational |
| `under_maintenance` | minor |
| `degraded_performance` | minor |
| `partial_outage` | major |
| `major_outage` | critical |

### 4.1 Claude AI — Anthropic — `https://status.claude.com` (Statuspage)
| Key | Label | Exact match | Fallback pattern | Primary |
|---|---|---|---|---|
| `claude-code` | Claude Code | `claude code` | `\bclaude code\b` | ✅ |
| `claude-api` | API | `claude api (api.anthropic.com)` | `\bapi\b` | ✅ |
| `claude-web` | Claude.ai | `claude.ai` | `\bclaude\.ai\b` | ✅ |
| `claude-console` | Console | `claude console (platform.claude.com)` | `\bconsole\b` | ✅ |
| `claude-cowork` | Cowork | `claude cowork` | `\bcowork\b` | — |

### 4.2 GitHub Copilot — GitHub — `https://www.githubstatus.com` (Statuspage)
| Key | Label | Exact match | Fallback pattern | Primary |
|---|---|---|---|---|
| `copilot` | Copilot | `copilot` | `^copilot$` | ✅ |
| `copilot-models` | AI Models | `copilot ai model providers` | `copilot.*model` | ✅ |
| `codespaces` | Codespaces | `codespaces` | `\bcodespaces\b` | ✅ |
| `actions` | Actions | `actions` | `^actions$` | ✅ |
| `github-api` | API Requests | `api requests` | `\bapi requests\b` | — |

### 4.3 OpenAI — `https://status.openai.com` (Statuspage)
Developer surfaces only — no Sora/Images/Voice.
| Key | Label | Exact match | Fallback pattern | Primary |
|---|---|---|---|---|
| `codex-api` | Codex API | `codex api` | `^codex api$` | ✅ |
| `codex-web` | Codex Web | `codex web` | `^codex web$` | ✅ |
| `vscode-extension` | VS Code Ext | `vs code extension` | `vs ?code extension` | ✅ |
| `chat-completions` | Chat API | `chat completions` | `^chat completions$` | ✅ |
| `responses` | Responses | `responses` | `^responses$` | — |
| `codex-cli` | CLI | `cli` | `^cli$` | — |

### 4.4 Gemini — Google — `https://status.cloud.google.com` (flat incident feed)
No Statuspage. `incidents.json` is filtered by AI keywords (`gemini`, `ai studio`, `vertex ai`, `generative ai`, `ai platform`, `cloud ai`); component states are derived from *active* incidents.
| Key | Label | Pattern | Primary |
|---|---|---|---|
| `gemini-api` | Gemini API | `\bgemini\b` | ✅ |
| `ai-studio` | AI Studio | `\bai studio\b` | ✅ |
| `vertex-ai` | Vertex AI | `\bvertex ai\b` | ✅ |

Google severity → impact: `high`/`critical` → critical, `medium` → major, else minor.

---

## 5. Functional requirements

### 5.1 Monitoring

- **FR-1** On launch, the app performs a status check immediately, then on the configured interval.
- **FR-2** All four services are checked concurrently; within a Statuspage service the three endpoints are also fetched concurrently. A failure of any one leg degrades only that leg.
- **FR-3** A service that fails entirely reports `unknown` with its error message retained for the popover's diagnostics row.
- **FR-4** A whole-check failure retries up to 3 times with linear backoff (2 s, 4 s, 6 s) before writing the "Unable to check status" state.
- **FR-5** Requests carry a 10-second timeout and bypass the local cache.
- **FR-6** The app re-checks on: display wake, system wake, network path becoming satisfied, popover opening when data is older than 30 s, and explicit user refresh.
- **FR-7** When offline, the app enters an explicit **Offline** presentation — distinct from `unknown` — and does not burn retries. It resumes on the next satisfied network path.
- **FR-8** Incidents are pruned to the 10 most recent and to a 14-day window before persistence.
- **FR-9** A disabled service (§5.2) is not fetched and does not contribute to the combined roll-up.

### 5.2 Settings

All settings live in `UserDefaults` under the app's suite and are exposed in a native Settings window with four tabs.

**General**
| Setting | Type | Default |
|---|---|---|
| Refresh interval | 1 / 2 / 5 / 10 / 15 / 30 min | 5 min |
| Launch at login | Bool (`SMAppService.mainApp`) | off |
| Show in Dock as well as menu bar | Bool | off (`LSUIElement`) |
| Global hotkey to toggle popover | Recorder, default unset | unset |
| Check on wake / on network restore | Bool | on |
| Close the popover after | Stay open / 5 / 10 / 15 / 30 s / 1 min | 15 s |

**Services**
| Setting | Type | Default |
|---|---|---|
| Enable Claude / GitHub / OpenAI / Gemini | Bool ×4 | all on |
| Per-service: which components appear on the card | multi-select over the registry, seeded from `primary` | registry default |
| Card order | drag to reorder | Claude, GitHub, OpenAI, Gemini |

**Notifications**
| Setting | Type | Default |
|---|---|---|
| Notify on degradation (operational → worse) | Bool | on |
| Notify on recovery (worse → operational) | Bool | on |
| Minimum severity to notify | minor / major / critical | minor |
| Only notify for primary components | Bool | on |
| Play sound | Bool | off |
| Quiet hours | time range (may wrap midnight) | off, 22:00–08:00 |
| Notification cooldown per component | 5 / 15 / 60 min | 15 min |

**Appearance**
| Setting | Type | Default |
|---|---|---|
| Menu bar icon style | Hub / Pulse / Minimal dot (see [ICONS.md](docs/ICONS.md) §3) | Hub |
| Colour the icon by status, vs. monochrome + status pip | enum | monochrome + pip (the macOS-native choice) |
| Show affected-count badge on the icon | Bool | on |
| Show status text next to the icon | off / short label / affected count | off |
| Animations | Full / Subtle / Off (also forced Off by system Reduce Motion) | Full |
| Accent theme | System / Vibe (cyan-teal) | Vibe |

### 5.3 Menu bar item

- **FR-10** Left click toggles the popover. Right click (or ⌃-click) opens a compact `NSMenu`: Refresh Now, per-service jump-to-status-page, Settings…, About, Quit.
- **FR-11** The glyph reflects the combined indicator at all times; the tooltip reads `Vibe Stats vX.Y.Z — <label>[ (N affected)]`, matching the extension's title string.
- **FR-12** Badge text mirrors the extension: affected count when non-operational, `!` when the count is zero for major/critical, `?` for minor-with-zero and for unknown, nothing when operational.
- **FR-13** The icon never animates continuously while operational at Subtle/Off; at Full it uses a slow ambient breath (see [DESIGN.md](docs/DESIGN.md) §5).

### 5.4 Popover

- **FR-14** Header: brand mark, version, combined status banner, last-updated relative time, refresh control.
- **FR-15** A 2-column grid of service cards, each with: vendor accent bar, icon, name, subtitle (vendor, or the degraded component list), status chip, primary component rows, and an incidents disclosure.
- **FR-16** A component row shows label, state dot, and short state text (`OK`/`DEGRADED`/`PARTIAL`/`OUTAGE`/`UNKNOWN`). An unmatched component's tooltip explains that no component of that name exists on the status page; a matched one shows `<vendor name> — <raw status>`.
- **FR-17** When `pageIndicator != indicator`, the card shows a small inline "page: <label>" chip explaining the divergence.
- **FR-18** The incidents disclosure lists at most 5, `affectsWatched` first, each with title+date, status tag, affected components, relative time, and the first update body truncated to 140 characters.
- **FR-19** Clicking a card (outside interactive controls) opens the vendor status page in the default browser.
- **FR-20** A 7-day uptime sparkline per service, sourced from the local history log.
- **FR-21** ⌘R refreshes; Esc closes; Tab cycles focus; every control is VoiceOver-labelled.
- **FR-21a** The popover closes itself after the configured idle interval. The countdown is **visible** (a depleting hairline under the header, amber for the final 4 seconds), **pausable** (the pointer entering the popover pauses it; leaving restarts it from full), and **defeatable** (a pin button stops it for that visit; "Stay open" disables it entirely). It exits by scaling toward its menu bar anchor and fading, and skips the animation under Reduce Motion.

### 5.5 Notifications

- **FR-22** After each successful check, the coordinator diffs the new per-component indicators against the previous snapshot and emits notifications per the rules in §5.2, subject to per-component cooldown and quiet hours.
- **FR-23** The first check after launch never notifies — there is no prior state to diff against.
- **FR-24** A notification's action opens the popover.
- **FR-25a** Three or more transitions within one service are announced as a single grouped notification rather than a burst.
- **FR-25b** Transitions into or out of `unknown` are never announced.

### 5.6 Data & privacy

- **FR-25** The app makes network requests to exactly five hosts: `status.claude.com`, `www.githubstatus.com`, `status.openai.com`, `status.cloud.google.com`, and (only if the update check is enabled) the release feed host.
- **FR-26** No data leaves the machine. No analytics, no crash reporting, no identifiers.
- **FR-27** All state is stored unencrypted in `~/Library/Application Support/VibeStats/` and `~/Library/Preferences/`; it contains only public vendor status data and the user's settings.
- **FR-28** The About window links the same privacy policy the extension publishes.

---

## 6. Non-functional requirements

| # | Requirement |
|---|---|
| NFR-1 | **Deployment target macOS 26.0 or later.** Single-version target — no back-deployment. Rationale in [ARCHITECTURE.md](docs/ARCHITECTURE.md) §2 |
| NFR-2 | Universal binary (arm64 + x86_64) |
| NFR-3 | **Pure Swift, language mode 6, zero third-party runtime dependencies.** Built with the latest shipping toolchain (Swift 6.4 / Xcode 27 as of this writing). SwiftUI + AppKit + Foundation + UserNotifications + ServiceManagement + Network only. `-strict-concurrency=complete` and approachable concurrency on |
| NFR-4 | Idle CPU ≈ 0%; a full check completes in < 2 s on a warm connection and costs < 200 KB of transfer |
| NFR-5 | Resident memory < 60 MB with the popover closed |
| NFR-6 | Strict concurrency checking on; no data races; `@MainActor`-isolated UI, actor-isolated store |
| NFR-7 | Full VoiceOver support; honours Reduce Motion, Reduce Transparency, Increase Contrast, and Dynamic Type |
| NFR-8 | Light and dark appearance both first-class, and the app adopts the macOS 26 **Liquid Glass** material system rather than emulating it |
| NFR-9 | Localisable — no string concatenation for user-facing copy; `String(localized:)` throughout. Ship `en` only in v1.0 |
| NFR-10 | App Sandbox on, with `com.apple.security.network.client` as the only entitlement |
| NFR-11 | Hardened Runtime, Developer ID signed, notarized, stapled |
| NFR-12 | Cold launch to menu bar icon visible in < 400 ms |
| NFR-13 | Menu bar glyph remains legible against the macOS 26 transparent menu bar over arbitrary wallpapers (see [ICONS.md](docs/ICONS.md) §2.6) |

---

## 7. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| 7.1 | Deployment target | **macOS 26.0, no back-deployment.** Targeting one modern OS buys Liquid Glass materials, Icon Composer app icons with automatic light/dark/tinted/clear variants, Swift 6.2 concurrency defaults, and the current SwiftUI surface — all of which this app leans on directly. Supporting 14/15 would mean maintaining a parallel visual language for the whole UI |
| 7.2 | `MenuBarExtra` vs `NSStatusItem` | **`NSStatusItem` + `NSPopover`** — the custom animated glyph, right-click menu, and badge drawing all need AppKit-level control. SwiftUI is hosted inside the popover |
| 7.2b | Swift version | **Track the latest shipping Swift 6.x** — 6.4 / Xcode 27 as built. Language mode is pinned at 6 in `project.yml`; the toolchain is pinned in `.xcode-version` so CI and local builds agree |
| 7.3 | Auto-update mechanism | v1.0 ships a "check for updates" that opens the GitHub Releases page. Sparkle is a v1.1 consideration and would break NFR-3 |
| 7.4 | User-defined services | Out of scope for v1.0. Design the registry as decodable so a future `~/Library/Application Support/VibeStats/services.json` overlay is additive |
| 7.5 | Shared code with the extension | None. Two implementations, one spec. The registry tables in §4 are the contract; a test asserts the Swift registry matches a JSON export of `services.js` |
| 7.6 | Distribution channel | Developer ID + notarized DMG via GitHub Releases, matching the extension's "not in a marketplace" posture. Mac App Store is a later decision |

---

## 8. Acceptance criteria for v1.0

Status against the criteria below, as built:

| # | Criterion | State |
|---|---|---|
| 1 | PARITY rows behave identically against recorded fixtures | ✅ |
| 2 | Unit tests over mapping, roll-up, matching, pruning, normalisers | ✅ 126 tests / 19 suites |
| 3 | Page-major + components-green reads Operational with a divergence chip | ✅ |
| 4 | A missing registry component reads UNKNOWN, and unresolved counts are visible | ✅ |
| 5 | Network loss produces the Offline presentation and recovers cleanly | ⚠️ implemented, not yet exercised on real hardware |
| 6 | Wake produces a check within 5 s | ⚠️ implemented, not yet exercised on real hardware |
| 7 | One notification per transition, none inside the cooldown | ✅ |
| 8 | Reduce Motion disables every animation; VoiceOver reads every surface | ⚠️ Reduce Motion is gated centrally; a full VoiceOver pass is outstanding |
| 9 | Passes notarytool and launches from a quarantined DMG | ⬜ `make notarize` written, never run |
| 10 | Menu bar icon legible at every scale, appearance and wallpaper | ✅ verified live and by contact sheet |
| 11 | App icon correct in all four macOS 26 appearances | ⚠️ classic asset catalogue ships; Icon Composer `.icon` is a manual pass |

### Original criteria

1. Every row of the parity matrix in §3 marked PARITY behaves identically to the extension against the same recorded API fixtures.
2. Unit tests cover `mapComponentStatus`, `mapPageIndicator`, `rollUp`, `matchComponent` (including the `claimed`-set stealing case), `pruneIncidents`, and both incident normalisers, with fixtures captured from the live endpoints.
3. With a fixture where GitHub's page indicator is `major` but every watched Copilot component is `operational`, the GitHub card reads **Operational** and shows the divergence chip.
4. With a fixture where a registry component name is absent from the payload, that component reads **UNKNOWN** — never OK — and the service's `componentsResolved < componentsWatched` is visible in diagnostics.
5. Killing the network mid-check produces the Offline presentation and a clean recovery on restore, with no lost timer.
6. Sleeping the machine for an hour and waking it produces a check within 5 seconds of wake.
7. A component transitioning operational → major produces exactly one notification, and a second transition inside the cooldown produces none.
8. Reduce Motion disables every animation; VoiceOver reads the combined status, each card's status, and each component row.
9. The app passes `xcrun notarytool` and launches from a quarantined DMG on a clean machine.
10. Menu bar icon is legible at every scale factor, in light and dark menu bars, over a light and a dark wallpaper through the macOS 26 transparent menu bar, and in the "reduced" menu bar of a notched display.
11. The app icon is authored in Icon Composer and renders correctly in all four macOS 26 appearances (default, dark, clear, tinted) at every Dock size.
