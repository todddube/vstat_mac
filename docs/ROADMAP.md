# Roadmap & Build Plan — Vibe Stats for macOS

Target: **macOS 26.0+**, Swift 6.2+ (Xcode 26 toolchain), language mode 6, strict concurrency complete, `-default-isolation MainActor`.

---

## Milestones

### M0 — Skeleton ✅
`project.yml` (XcodeGen) → `VibeStats.xcodeproj`. `LSUIElement = true`, sandbox on with only `com.apple.security.network.client`, `.xcode-version` and `.swift-version` pinned. An `NSStatusItem` appears with a placeholder SF Symbol and a Quit menu. Nothing else.

**Done when:** the app builds clean with strict concurrency, launches, shows an icon, quits.

### M1 — Domain ✅
`StatusIndicator`, `RollUp`, `ServiceRegistry`, `ComponentDefinition`, snapshot types. Transcribed from specs.md §4.

**Done when:** unit tests cover every mapping table, `RollUp`'s all-unknown and mixed-unknown cases (REVIEW.md §3.1), and `matchComponent`'s claimed-set stealing case. No networking exists yet.

### M2 — Engine ✅
`StatusAPIClient` with request-level retry, `StatuspageAdapter`, `GoogleCloudAdapter`, `IncidentNormalizer`, pruning. Fixtures captured live from all four vendors, plus the mutated variants in ARCHITECTURE.md §10.

**Done when:** a `check()` against fixtures produces a `Snapshot` matching hand-verified expectations, including the page-major/components-green case and the renamed-component case.

### M3 — Coordination & persistence ✅
`MonitorCoordinator`, `SnapshotStore`, `HistoryLog`, wake/network observers, `Preferences`.

**Done when:** the app polls on its interval, restores the last snapshot at launch, enters and leaves offline cleanly, and re-checks within 5 s of wake.

### M4 — Menu bar glyph ✅
`VibeHubGeometry`, `VibeHub` shape, `VibeIconRenderer`, `StatusItemController`, badge compositing, both rendering modes, the frame ticker.

**Done when:** every state in ICONS.md §2.2 renders correctly, snapshot tests pass at 1× and 2×, the glyph is legible over a light and a busy wallpaper through the transparent menu bar, and idle CPU with Motion.off is 0.0%.

### M5 — Popover ✅
`PopoverView`, `ServiceCardView`, `ComponentRowView`, `IncidentListView`, `SparklineView`, theme tokens, Liquid Glass surfaces, motion catalogue M3/M5–M11.

**Done when:** every state in DESIGN.md §4.5 has a working preview, both appearances are correct, and the divergence chip and unresolved footnote appear on the right fixtures.

### M6 — Settings & notifications ✅
Four settings tabs, `SMAppService` launch-at-login, `NotificationDispatcher` with cooldown and quiet hours, global hotkey.

**Done when:** a fixture-driven transition emits exactly one notification, a second inside the cooldown emits none, and the first snapshot after launch emits none.

### M7 — App icon & polish ✅
`VibeStats.icon` authored in Icon Composer from the layers in ICONS.md §4, About window, DMG background, accessibility pass.

**Done when:** the icon renders correctly in all four macOS 26 appearances at every Dock size, and a full VoiceOver pass reads every surface.

### M8 — Release (1 day)
Hardened Runtime, Developer ID signing, `notarytool` submit + staple, DMG, GitHub release.

**Done when:** a quarantined DMG downloaded on a clean machine launches without a Gatekeeper prompt.

**Total: ~14 working days.**

---

## Test plan

| Level | Coverage |
|---|---|
| Unit — Domain | Mapping tables, roll-up (incl. REVIEW.md §3.1 regressions), matcher, pruning boundaries |
| Unit — Engine | All fixtures × all adapters; failure injection: 500, timeout, malformed JSON, empty payload, renamed component |
| Contract | Swift registry == JSON export of `services.js`, field by field (specs.md §7.5) |
| Lint | No fallback regex matches more than one component in the live payloads (REVIEW.md §3.6) |
| Coordination | Injected `Clock` and fake wake/network signals: timer re-arm, offline suspension, notification cooldown, no-notify-on-first-snapshot |
| Snapshot | Icon renderer × every state × light/dark × 1×/2× |
| Manual | The macOS 26 checklist in ICONS.md §2.6; VoiceOver; Reduce Motion; Reduce Transparency; Increase Contrast; Dynamic Type at `.accessibility1` |

`make fixtures` re-captures live vendor payloads so schema drift shows up as a reviewable diff rather than a field report.

---

## Fixes worth back-porting to the extension

Independent of this project, two defects found in the review are worth a patch to `vstat` itself:

1. **REVIEW.md §3.1** — `rollUpStatus` returning `operational` for an all-unknown input, which can render "All dev tools are vibing!" during a total API blackout. A one-line fix in `services.js` plus a test.
2. **REVIEW.md §3.2** — retry logic that `Promise.allSettled` renders unreachable. Move retry into `fetchJson`.

Both are small, both are user-visible, and fixing them in the extension first gives the port a verified reference implementation to match.

---

## Post-1.0

| Idea | Note |
|---|---|
| User-defined services via a `services.json` overlay | Design the registry decodable now (specs.md §7.4) so this is additive |
| Menu bar history popover — a 24-hour timeline across all services | The `HistoryLog` already carries the data |
| Focus/Do-Not-Disturb awareness | Suppress notifications, keep the glyph accurate |
| Widget / Control Center control | Same snapshot, different presentation surface |
| Shortcuts action — "Get AI tool status" | Cheap, and makes the data scriptable |
| Sparkle-based auto-update | Would break the zero-dependency rule; weigh against it |
