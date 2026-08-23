# Review — Vibe Stats browser extension v1.3.1

A read of the whole extension (2,709 lines across 6 source files) ahead of the macOS port. This documents what it does, what is worth preserving verbatim, and the defects the Swift implementation must not inherit.

---

## 1. What the extension is

An MV3 extension for Chrome/Edge and Safari that polls four vendor status APIs every 5 minutes, resolves a curated list of components out of each payload, rolls those up into a single indicator, persists the result, and renders it in a 400×480 popup.

```
manifest.json ──► src/background.js            MV3 entry: lifecycle, alarm, messages
                   ├── src/core/status-monitor.js   VStateMonitor — all fetching & logic
                   │     └── src/core/services.js   registry + status mapping (the contract)
                   └── src/platform/browser-shim.js chrome.* vs browser.* normalisation
                  src/popup/popup.{html,js}     VStatePopupController — pure renderer
```

The file boundaries are genuinely good. `services.js` is a declarative contract, `status-monitor.js` is pure logic over it, the popup renders from the same registry so the UI cannot drift from what is watched, and every browser API call is funnelled through one shim. **The macOS port should keep this exact shape** — registry / engine / presentation — because it is the reason a second implementation is cheap.

---

## 2. What is worth preserving verbatim

### 2.1 Component roll-up over page indicator
The load-bearing idea. Vendors publish a single page-level indicator that answers "is anything at this company broken", which is the wrong question for a developer watching Copilot. Rolling up from a curated component list, and keeping the page indicator alongside as `pageIndicator` purely to show the disagreement, is correct and is the product.

### 2.2 `matchComponent`'s two-tier matching with a `claimed` set
Exact name first, regex as fallback, and a `claimed` set so a loose pattern cannot steal an earlier entry's component. The comment naming the concrete failure it prevents (`/chatgpt/` matching "Codex in ChatGPT Desktop" twice) is exactly the kind of comment that survives a port.

### 2.3 Unmatched → `unknown`, never `operational`
Stated explicitly in the code and in CLAUDE.md. A monitor that silently reports a component it can no longer find as healthy is worse than no monitor. Preserve.

### 2.4 Failure isolation
`Promise.allSettled` at both levels — across services, and across the three Statuspage endpoints within a service. One vendor's outage or schema change degrades one card, never the app.

### 2.5 The security posture of the popup
No `innerHTML` anywhere; every vendor-supplied string goes through `textContent`. Vendor incident bodies are untrusted input and are treated that way.

### 2.6 The honest MV3 note about badge animation
The code comments record that the old `setInterval` badge flasher could not work under MV3 — the worker is killed long before the timer fires — and that Safari ignores badge colour entirely. That decision log is valuable; the macOS app is precisely where that ambition becomes possible again.

---

## 3. Defects

Ordered by severity. Each names the fix the Swift implementation must adopt.

### 3.1 🔴 Total API failure renders as "All dev tools are vibing!"

`rollUpStatus` seeds its reduce with `'operational'` and `worstStatus` compares by `STATUS_PRIORITY`, where `unknown = 0` — **below** `operational = 1`.

```js
export const STATUS_PRIORITY = { unknown: 0, operational: 1, minor: 2, major: 3, critical: 4 };
export function rollUpStatus(indicators) {
  const known = indicators.filter(Boolean);          // 'unknown' is truthy — it survives
  if (known.length === 0) return 'unknown';
  return known.reduce((worst, next) => worstStatus(worst, next), 'operational');
}
```

`rollUpStatus(['unknown','unknown','unknown','unknown'])` returns **`'operational'`**.

The consequence chain: if every fetch fails, `checkAllStatuses` still resolves (nothing throws — `allSettled` never rejects), each service becomes `unknownService(...)` with `indicator: 'unknown'`, `combineStatuses` rolls those four up to `operational`, and `describeCombined('operational')` returns the literal string **"All dev tools are vibing!"**. Green banner, green badge, no data. The same masking happens one level down: a service where 2 of 5 components resolve to `unknown` reports `operational` and the unknowns are invisible in the roll-up.

This directly contradicts §2.3 — the code refuses to call an unmatched *component* operational, then the roll-up does it anyway.

> **macOS fix (required).** `unknown` must not be rankable against real states. Roll-up returns `unknown` when *every* input is unknown; otherwise it returns the worst of the non-unknown inputs **and carries an `unresolvedCount`** that the UI surfaces as a "N components unresolved" chip. `describeCombined` must never emit the vibing string while any service is unknown. Acceptance criteria specs.md §8.4 and the `rollUp` unit tests exist for this.

### 3.2 🟠 The retry path is effectively dead code

`checkAllStatuses` wraps everything in `try/catch` and retries up to 3 times with linear backoff — but the only `await` inside the `try` that can reject is `persist()` / `updateBadgeIcon()`, because `Promise.allSettled` never rejects. Every real network failure is swallowed into an `unknownService` entry *before* the retry logic can see it. So a transient DNS blip costs a full 5-minute interval instead of a 2-second retry.

> **macOS fix.** Retry belongs at the *request* level, not around the whole sweep: retry an individual `fetchJson` on transient failures (timeout, connection lost, 5xx), and keep the sweep-level `TaskGroup` non-throwing. Do not retry 4xx.

### 3.3 🟠 `browser-shim.invoke()` can hang forever

```js
try {
  maybePromise = fn.apply(thisArg, [...args, cb]);
} catch (error) {
  try { maybePromise = fn.apply(thisArg, args); }   // retry without callback
  catch (retryError) { reject(retryError); return; }
}
if (maybePromise && typeof maybePromise.then === 'function') { ... }
```

If the callback-style call throws and the retry returns a non-thenable (a synchronous API — `alarms.create` is one), the promise is neither resolved nor rejected. Nothing times out. Callers `await` forever. `runtime.sendMessage` is the only shim function with its own timeout guard; the rest have none.

> **macOS fix.** Not portable — the shim disappears entirely. But the lesson does port: **every await in the coordinator must be bounded**, either by `URLSession`'s timeout or by an explicit `Task` timeout wrapper.

### 3.4 🟡 `minor` with zero affected components and `unknown` both render as `?`

```js
} else if (indicator === 'minor') { badgeText = affectedCount > 0 ? String(affectedCount) : '?'; }
else if (indicator === 'unknown') { badgeText = '?'; }
```

Two materially different states — "degraded but we can't say which component" and "we have no idea" — are indistinguishable in the toolbar.

> **macOS fix.** The menu bar glyph carries state in colour/shape, not only in a text badge; `unknown` gets its own hollow-node treatment. See ICONS.md §4.

### 3.5 🟡 The toolbar icon never changes

`updateBadgeIcon` calls `toolbar.setIcon` with the same four static PNGs on every single check. Status lives **only** in badge text and badge colour — and Safari ignores badge colour. On Safari, a critical outage and full health look identical unless you read the badge digit.

> **macOS fix.** This is the port's headline improvement: the glyph itself is the status display. Colour, fill, and motion all carry state, with a monochrome-plus-pip mode for users who want a native-looking menu bar.

### 3.6 🟡 Claude's `\bapi\b` fallback pattern is dangerously loose

`claude-api` falls back to `/\bapi\b/i`. If Anthropic renames "Claude API (api.anthropic.com)", that pattern matches essentially any component whose name contains "API". The `claimed` set bounds the damage to one wrong claim, and registry order means `claude-code` matches first, but the entry can still bind to an unrelated component and report its status under the label "API" — a silent wrong answer, which is worse than `unknown`.

> **macOS fix.** Tighten to `/\bclaude api\b|\bapi\.anthropic\.com\b/i` and add a lint test asserting no fallback pattern matches more than one component in the current live payload. `github-api`'s `\bapi requests\b` and OpenAI's anchored patterns are fine as-is; `codex-cli`'s `^cli$` is fine because it is anchored.

### 3.7 🟡 Non-primary components are invisible but affect the verdict

Only `primary: true` components render rows, yet every component feeds the roll-up. A user can see four green rows on the Claude card above a "Degraded" chip, with the explanation only in the subtitle text (which does list affected labels) — and nowhere at all if the degraded component is also the one truncated out of the subtitle by `text-overflow: ellipsis`.

> **macOS fix.** A component that is non-operational is *always* shown, regardless of its `primary` flag; `primary` governs only the default-visible set when everything is healthy. Users can additionally opt into "show all components" per service (specs.md §5.2).

### 3.8 🟡 Popup is light-mode only and not keyboard accessible

`popup.html` defines one palette with no `prefers-color-scheme: dark` block. Separately, CLAUDE.md claims "Accessibility: ARIA labels and keyboard navigation support" — there is not a single `aria-*` attribute in `popup.html`, the service cards are `<div>`s with click handlers (not focusable, not activatable by keyboard), and only the toggle/refresh/about buttons are reachable by Tab.

> **macOS fix.** Both appearances are first-class, every card is a real button, and VoiceOver coverage is an acceptance criterion (specs.md §8.8).

### 3.9 ⚪ Documentation drift

- CLAUDE.md: "Popup auto-refreshes every 30 seconds when open" — the code says `AUTO_REFRESH_MS = 120000` (2 minutes). The 30 s constant is `STALE_AFTER_MS`, used only on `visibilitychange`.
- CLAUDE.md: "Manual refresh available via Ctrl+R" — true, and also F5, undocumented.
- CLAUDE.md storage schema omits `<service>Components`, which `persist()` does write.
- `dev/icon-generator/` is documented in the project structure but the directory does not exist; the icon tooling that survives is `design/cool-vibe-icons.html`.

### 3.10 ⚪ Asymmetry between the two adapters

The Statuspage adapter can report a component as `unknown`; the Google adapter cannot — a component with no matching active incident is unconditionally `operational`. That is defensible (Google publishes no per-component health, only incidents), but it means "Gemini API: OK" is a weaker claim than "Claude Code: OK" and nothing in the UI says so.

> **macOS fix.** Tag the Gemini card's components with an "incident-derived" provenance marker and explain it in the tooltip. Same data, honest framing.

---

## 4. Things that simply do not port

| Extension concern | Why it disappears |
|---|---|
| `browser-shim.js` (230 lines) | One platform, one set of APIs |
| MV3 worker-termination defences (`getMonitor()` rebuild, cold-start alarm re-arm, no module-scope state) | A native app has a stable process and a real timer |
| `runtime.onMessage` request/response plumbing | Direct method calls on a coordinator |
| Safari module-graph flattening (`BACKGROUND_MODULE_GRAPH`), nested bundle-id rules | Build-system artefacts of the Safari converter |
| Legacy duplicate storage keys (`<id>Status`, `<id>Incidents`, `<id>Components`) | Nothing consumes them but old popups and the test suite |
| `host_permissions` | Sandboxed network client entitlement covers it |

Roughly **40% of the extension's line count is platform ceremony**. The macOS app should land at a similar or smaller size while doing considerably more.

---

## 5. What the port should add, ranked by value

1. **Transition notifications.** The single most valuable thing a native process can do that MV3 cannot. The extension can only tell you something is wrong when you happen to click it.
2. **A status-bearing icon.** Ambient awareness with zero interaction — the actual reason to want a menu bar app.
3. **Sleep/wake and network-change awareness.** A laptop closed for four hours currently shows four-hour-old data with a cheerful green badge.
4. **Uptime history.** "Was Claude Code down at 2pm, or was it me?" is unanswerable today because nothing is retained beyond the last snapshot.
5. **A real settings surface.** Interval, per-service enable, and notification policy are all hardcoded today.

---

## 6. Verdict

The extension's core logic is well-factored, well-commented, and built on a genuinely correct product insight. Two defects are serious — the `unknown`-ranks-below-`operational` roll-up (§3.1), which can display "All dev tools are vibing!" during a total blackout, and the dead retry path (§3.2) — and both are worth fixing **in the extension too**, not just avoiding in the port.

Everything else is either cosmetic, a platform limitation the port removes for free, or documentation drift.

The registry in `services.js` is the asset. It should be treated as the shared contract between the two implementations, with a test on the Swift side asserting the two stay in agreement (specs.md §7.5).
