# Design — Vibe Stats for macOS

The extension's popup is competent and generic: system font, slate greys, four coloured cards. It reads like a dashboard template. The macOS app should read like **an instrument** — something with a signal in it, closer to a synth's level meter or an aircraft annunciator panel than to a Bootstrap card grid.

The organising idea is the one already in the icon: **a hub with spokes**. Four services radiate from one centre. That geometry is the app icon, the menu bar glyph, the loading state, and the empty state. Everything else is quiet so the signal is loud.

---

## 1. Design principles

1. **Status is carried by more than colour.** Colour + fill + shape + motion, always at least two. Red/green alone fails ~8% of men.
2. **Green is silent.** When everything is fine the interface is nearly monochrome. Colour appears only where something is wrong, so a glance costs nothing.
3. **Motion means "this changed"**, never decoration. Nothing loops forever except one 6-second ambient breath, and only at Full motion.
4. **Dark is the primary appearance**, light is fully supported. The instrument reads best on dark; the menu bar glyph must work on both — and on macOS 26 it must also work against a *transparent* menu bar over an arbitrary wallpaper.
5. **Use the system's Liquid Glass, don't imitate it.** Popover chrome, the settings window, and controls take the platform materials as-is. The only place the app asserts its own visual identity is the hub mark and the status palette — everything else should feel like it shipped with the OS.
6. **No invented data.** An unknown is drawn as an absence — a hollow ring — not as a colour.

---

## 2. Colour

Semantic tokens only; no view names a hex value. Values are given for dark / light.

### 2.1 Status

| Token | Dark | Light | Used for |
|---|---|---|---|
| `status.operational` | `#22D3A5` | `#0E9F6E` | teal-green, deliberately *not* the stoplight green — it reads as "instrument nominal" |
| `status.minor` | `#F5B23B` | `#B45309` | |
| `status.major` | `#FB7A3C` | `#C2410C` | |
| `status.critical` | `#F2545B` | `#DC2626` | |
| `status.unknown` | `#6B7A8F` | `#64748B` | always paired with a hollow shape |
| `status.offline` | `#4A5568` | `#94A3B8` | distinct from unknown (REVIEW.md §3.4) |

Each has a `.dim` variant at 18% alpha for backgrounds and a `.glow` at 35% for shadows.

### 2.2 Brand & surface

| Token | Dark | Light |
|---|---|---|
| `brand.vibe` | `#22D3EE` cyan — the hub colour, carried from the extension icon | `#0891B2` |
| `brand.vibeDeep` | `#0E7490` | `#155E75` |
| `surface.base` | `#0E1420` | `#F7F9FC` |
| `surface.raised` | `#161E2E` | `#FFFFFF` |
| `surface.sunken` | `#0A0F18` | `#EEF2F7` |
| `stroke.hairline` | `#FFFFFF` @ 8% | `#0F172A` @ 8% |
| `text.primary` | `#E8EEF7` | `#0F172A` |
| `text.secondary` | `#9AA9BF` | `#475569` |
| `text.tertiary` | `#61708A` | `#94A3B8` |

### 2.3 Vendor accents (carried from the extension)

| Service | Dark | Light |
|---|---|---|
| Claude | `#E08C3C` | `#D97706` |
| GitHub | `#A78BFA` | `#7C3AED` |
| OpenAI | `#34D399` | `#059669` |
| Gemini | `#60A5FA` | `#2563EB` |

Accents appear **only** as a 2 pt top rule on each card and in the card's monogram tile. They never encode status — that is the status token's job, and mixing the two is how the extension's cards get busy.

### 2.4 Contrast

Every text/background pair meets WCAG AA (4.5:1) in both appearances. Status dots are never the sole carrier of meaning: every dot is accompanied by its `compactTitle` text (`OK` / `DEGRADED` / `PARTIAL` / `OUTAGE` / `UNKNOWN`), exactly as the extension does.

---

## 3. Typography

| Role | Font | Size / weight |
|---|---|---|
| Brand wordmark | SF Pro Rounded, Bold | 15 pt, tracking −0.2 |
| Banner headline | SF Pro Text, Semibold | 14 pt |
| Card title | SF Pro Text, Semibold | 13 pt |
| Card subtitle | SF Pro Text, Regular | 11 pt, `text.tertiary` |
| Component label | SF Pro Text, Medium | 12 pt |
| Component state | **SF Mono, Semibold** | 10 pt, uppercase, tracking +0.4 |
| Timestamps, counts, versions | **SF Mono, Regular** | 10–11 pt, tabular |
| Incident title | SF Pro Text, Semibold | 12 pt |
| Incident body | SF Pro Text, Regular | 11 pt, line height 1.45 |

The monospace on states and numbers is the whole typographic idea: it makes the readout feel measured rather than marketed, and it stops the component rows from jittering as states change width. All sizes scale with Dynamic Type.

---

## 4. Layout

### 4.1 Popover — 420 × 560 pt (grows with content, capped at 720 pt then scrolls)

```
╭──────────────────────────────────────────────────────────╮
│  ◈  VIBE STATS                    v1.0.0    ⟳    ⋯       │  header 56pt
│                                                          │
│  ╭──────────────────────────────────────────────────╮   │
│  │ ●  All dev tools are vibing                       │   │  banner
│  │    4 services · 18 components      updated 2m ago │   │  64pt
│  ╰──────────────────────────────────────────────────╯   │
│                                                          │
│  ╭─────────────────────╮  ╭─────────────────────╮       │
│  │▔▔▔▔▔▔▔▔▔▔▔▔▔ Claude │  │▔▔▔▔▔▔▔▔▔▔▔▔ GitHub  │       │  2-col grid
│  │ ⧉  Claude AI        │  │ ⧉  GitHub Copilot   │       │  190pt tall
│  │    Anthropic        │  │    GitHub           │       │
│  │  ● Operational      │  │  ● Degraded  page:▲ │       │  ← divergence chip
│  │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │  │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │       │
│  │  Claude Code    OK  │  │  Copilot   DEGRADED │       │
│  │  API            OK  │  │  AI Models      OK  │       │
│  │  Claude.ai      OK  │  │  Codespaces     OK  │       │
│  │  Console        OK  │  │  Actions        OK  │       │
│  │  ▁▂▁▁▁▁▁ 7d         │  │  ▁▁▄▂▁▁▁ 7d         │       │  ← sparkline
│  │  ⌄ Issues           │  │  ⌄ Issues (1)       │       │
│  ╰─────────────────────╯  ╰─────────────────────╯       │
│  ╭─────────────────────╮  ╭─────────────────────╮       │
│  │        OpenAI       │  │        Gemini       │       │
│  ╰─────────────────────╯  ╰─────────────────────╯       │
│                                                          │
│  Settings…                            Privacy · GitHub   │  footer 36pt
╰──────────────────────────────────────────────────────────╯
```

- 16 pt outer padding, 12 pt gutters, 12 pt card radius, 1 pt hairline border.
- The popover uses `.transient` behaviour on a **system Liquid Glass background** — `NSPopover`'s standard macOS 26 chrome, with `.glassEffect(in:)` on the banner and the card container so they refract the desktop consistently with the rest of the OS. Reduce Transparency collapses every glass surface to opaque `surface.raised`; the layout is identical either way.
- Cards are **buttons**: focusable, `↩`-activatable, and they open the vendor status page — fixing REVIEW.md §3.8.

### 4.2 Card anatomy

| Element | Behaviour |
|---|---|
| Accent rule | 2 pt, vendor accent, full card width at the top |
| Monogram tile | 26×26, radius 7, accent at 14% alpha, accent-coloured letterform |
| Title / subtitle | Subtitle is the vendor name, and flips to the degraded component list in `status.major` colour when anything is affected (≙ `.card-subtitle.affected`) |
| Status chip | Dot + label; background is the status `.dim`, border the status at 40% |
| Divergence chip | Appears only when `pageIndicator != indicator`; reads `page: Partial` with a ▲/▼ marker. This makes the extension's tooltip-only insight visible — it *is* the product's thesis (REVIEW.md §2.1) |
| Component rows | Primary components always; **plus any non-primary component that is non-operational** (REVIEW.md §3.7). Row = label · dot · mono state text |
| Unresolved footnote | `2 of 5 components unresolved` in `status.unknown` when `componentsResolved < componentsWatched` |
| Sparkline | 7-day, one column per 3-hour bucket, height = worst severity in the bucket, coloured by that severity. Flat teal when healthy — nearly invisible, which is the point |
| Issues disclosure | Count in the label; expands in place, pushing the grid — the panel is not a popup-in-a-popup |

### 4.3 Incident row

Left rule in the impact colour, title with date prefix, a status tag (`investigating` / `monitoring` / `resolved`), affected components (max 3, ellipsised), a relative time, and the first update body truncated to 140 characters. Ordering: `affectsWatched` first, then newest — identical to the extension.

### 4.4 Settings window — 620 × 460, four tabs

`General · Services · Notifications · Appearance`, a standard `TabView(.automatic)` in a `Settings` scene. Native `Form` with `LabeledContent`; no custom chrome. Settings should look like macOS, not like the popover — the popover is the instrument, settings is the manual.

The **Services** tab is the interesting one: a list of the four services, each expandable to its component registry with checkboxes for card visibility, showing the live matched vendor name and raw status beside each — turning the registry into a debugging surface for exactly the drift REVIEW.md §3.6 warns about.

### 4.5 Empty, loading, offline, error

| State | Presentation |
|---|---|
| First launch, no data | The hub glyph at 64 pt with spokes drawing in sequence, "Checking status…" |
| Refresh in progress | Header ⟳ rotates; cards keep their last values at 100% opacity (never blank data you already have) |
| Offline | Banner in `status.offline`, glyph hollow, "Offline — will resume automatically". Cards dim to 55% and keep their last-known values with a "as of 14:02" stamp |
| Total failure | `ContentUnavailableView`, "Unable to check status", a Retry button, and the underlying error in a disclosure. **Never** the vibing string (REVIEW.md §3.1) |

---

## 5. Motion

Three levels: **Full** (default), **Subtle**, **Off**. System Reduce Motion forces Off and disables the control with an explanatory note. Every animation below is listed with what it degrades to.

| # | Animation | Full | Subtle | Off |
|---|---|---|---|---|
| M1 | **Ambient breath** — the hub's centre node scales 1.0→1.06 and its glow 0.85→1.0 over 6 s, `easeInOut`, forever. The app's heartbeat: it says "still watching" without saying anything else | on | off | off |
| M2 | **Critical pulse** — a ring expands from the centre node to 1.8× and fades, every 1.4 s. Two concentric rings, offset 0.4 s | on | single ring, 2.5 s | static filled dot |
| M3 | **Status transition** — the glyph cross-fades colour over 350 ms while the affected spoke thickens 1.5 pt→2.5 pt and springs back (`.spring(response: 0.35, damping: 0.7)`) | on | 200 ms cross-fade | instant |
| M4 | **Refresh sweep** — a bright arc travels the hub's outer ring once per check, 900 ms, `easeInOut`. On the header button, a 360° rotation | on | rotation only | opacity 0.5 while busy |
| M5 | **Card state change** — the status chip's background flashes to the new status `.dim` at 1.6× brightness and settles over 500 ms | on | 250 ms, no overshoot | instant |
| M6 | **Component row stagger** — on popover open, rows fade+rise 4 pt with a 12 ms per-row stagger, 220 ms total | on | fade only | instant |
| M7 | **Disclosure** — incidents panel expands with `.spring(response: 0.32, damping: 0.82)`; the chevron rotates 180° | on | 180 ms ease | instant |
| M8 | **Sparkline draw** — bars grow from the baseline, 20 ms stagger, on first appearance only | on | off | off |
| M9 | **Popover appear** — scale 0.96→1.0 + fade, 180 ms, anchored at the status item | on | fade only | instant |
| M10 | **Badge count change** — the numeral rolls vertically (`.contentTransition(.numericText())`) | on | on | instant |
| M11 | **Degradation attention** — on a new degradation while the popover is open, the affected card's border pulses its status colour twice over 1.2 s | on | once | off |
| M12 | **Glass response** — cards use the system's built-in glass interaction (`.glassEffect(.regular.interactive())`) for hover and press, rather than a hand-written scale/shadow | system | system | system (system honours Reduce Motion itself) |

Rules that keep this from becoming noise:

- Only **one** looping animation exists (M1), and it stops entirely while the popover is open — the instrument is idle-facing.
- Motion never delays information. Every animated value is already correct at frame 0; the animation is the transition, not the reveal.
- No animation runs while the display is asleep, the app is hidden, or the status item is in an overflow menu bar.

```swift
// Motion.swift — one gate, checked everywhere.
@Observable final class Motion {
    var level: Level                   // .full | .subtle | .off
    var effective: Level {             // system Reduce Motion always wins
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .off : level
    }
    func animation(_ spec: Spec) -> Animation? { effective.resolve(spec) }
}
```

A `nil` animation is a valid `SwiftUI.Animation` argument that means "no animation" — so `withAnimation(motion.animation(.transition))` is the only call site pattern, and Off is honoured by construction rather than by remembering to check.

---

## 6. Sound

Off by default. When enabled, exactly two sounds, both short and non-alarming: a soft two-tone descending mark for degradation, ascending for recovery. Never plays for `unknown`, never during quiet hours, never more than once per cooldown window.

---

## 7. Accessibility

| Concern | Commitment |
|---|---|
| VoiceOver | The status item announces `Vibe Stats, <combined label>, <n> affected`. Each card is one button: `Claude AI, Degraded, 1 of 5 components affected, Claude Code partial outage`. Component rows are grouped so VO reads label+state as one phrase |
| Colour independence | Every status has text (`OK`/`DEGRADED`/…) and a distinct dot fill (filled / half / hollow / ringed) |
| Reduce Motion | Forces Motion.off (§5) |
| Reduce Transparency | Liquid Glass → opaque `surface.raised`; no layout change |
| Increase Contrast | Hairlines go to 20% alpha, status borders to 70%, chip text to `text.primary` |
| Dynamic Type | All text scales; cards reflow to a single column past `.accessibility1` |
| Keyboard | Full tab order, `↩` activates, `⌘R` refresh, `⌘,` settings, `Esc` closes, `⌘Q` quits. The global hotkey (opt-in) toggles the popover |
| Focus | Visible 2 pt `brand.vibe` focus ring on every control, never suppressed |

---

## 8. Copy

The extension's voice — "All dev tools are vibing!" — is worth keeping, but it must never be a lie. The rules:

| Condition | Copy |
|---|---|
| All operational, all resolved | `All dev tools are vibing` |
| All operational, some unresolved | `All watched components OK · N unresolved` |
| Minor | `Minor issues with <services>` |
| Major | `Major issues affecting <services>` |
| Critical | `Outage: <services>` |
| Any service unknown | `Status unavailable for <services>` — **never** the vibing string |
| All unknown | `Unable to check status` |
| Offline | `Offline — will resume automatically` |

Service lists use `ListFormatter` so they localise correctly. Nothing is built by string concatenation (NFR-9).
