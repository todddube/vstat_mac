# Icons — Vibe Stats for macOS

Two marks, one idea.

The extension's icon is a **hub**: a bright cyan centre node with six spokes out to six satellite nodes, on a dark rounded square. It is a good mark and it should survive the port — but it should also start *meaning* something.

## The idea: four spokes, four services

The macOS mark reduces the hub from six spokes to **four**, arranged as a diagonal X, and assigns each terminal node to one monitored service in a fixed, never-changing position:

```
        Claude ◆         ◆ GitHub
              ╲         ╱
               ╲       ╱
                ╲     ╱
                  ◉  ←── core (combined status)
                ╱     ╲
               ╱       ╲
              ╱         ╲
       Gemini ◆         ◆ OpenAI
```

The core carries the combined roll-up. Each node carries one service. This is why the reduction from six to four is not a simplification for its own sake — **the icon becomes a readout**. At a glance in the menu bar you can see not just *that* something is degraded but *which corner of your toolchain* it is.

Fixed positions, always, regardless of card ordering in the popover:

| Position | Service |
|---|---|
| Upper-left | Claude |
| Upper-right | GitHub Copilot |
| Lower-right | OpenAI |
| Lower-left | Gemini |

---

## 1. Geometry

Defined once, on a unit square, and scaled to every size. All values are fractions of the canvas edge.

| Element | Value |
|---|---|
| Canvas | 1.0 × 1.0, origin top-left, centre `(0.5, 0.5)` |
| Node ring radius | `0.30` |
| Node angles | 135°, 45°, 315°, 225° (i.e. the four diagonals) |
| Core radius | `0.085` |
| Node radius | `0.055` |
| Spoke width | `0.038` |
| Spoke inset | starts at `core + 0.02`, ends at `node − 0.02` — the spoke never touches either disc, which is what keeps it crisp at 16 pt |
| Core glow radius | `0.20` (rendered only above 32 pt) |
| Orbit ring | `0.42`, stroke `0.012` — app icon only |

At menu bar size the canvas is **18 × 18 pt** with the glyph drawn into the inner **16 × 16 pt**, matching the 2 pt breathing room every system menu bar icon leaves.

```swift
// VibeHubGeometry.swift — shared by the SwiftUI Shape and the NSImage renderer.
enum VibeHubGeometry {
    static let nodeRingRadius: CGFloat = 0.30
    static let coreRadius:     CGFloat = 0.085
    static let nodeRadius:     CGFloat = 0.055
    static let spokeWidth:     CGFloat = 0.038
    static let gap:            CGFloat = 0.02

    /// Fixed diagonal positions — index order matches ServiceID.allCases:
    /// claude (UL), github (UR), openai (LR), gemini (LL).
    static let nodeAngles: [Angle] = [.degrees(225), .degrees(315),
                                      .degrees(45),  .degrees(135)]

    static func node(_ index: Int, in rect: CGRect) -> CGPoint {
        let a = nodeAngles[index].radians
        let r = nodeRingRadius * rect.width
        return CGPoint(x: rect.midX + cos(a) * r, y: rect.midY + sin(a) * r)
    }
}
```

*(Angles are given in a y-down coordinate space, so 225° lands upper-left.)*

---

## 2. Menu bar glyph

### 2.1 Two rendering modes (Appearance setting, specs.md §5.2)

**A. Monochrome + status pip — the default, and the macOS-native answer.**
On macOS 26 the menu bar is transparent by default, so a template image is not merely conventional — it is the only rendering the system can guarantee stays legible as the wallpaper changes underneath it.
The hub is drawn as a **template image**, so the system tints it black/white to match the menu bar, matches the appearance of every other menu bar icon, and survives Increase Contrast and inverted displays for free. Status is carried by a **pip**: a 5 pt disc at the glyph's lower-right, drawn non-template so its colour survives.

To do this the icon is composited from two images — a template hub and a non-template pip — into one non-template `NSImage`, with the hub pre-tinted to the effective menu bar appearance. `NSAppearance.currentDrawing()` gives the right colour, and the icon is re-rendered on `AppleInterfaceThemeChangedNotification`.

**B. Full colour.** The hub is drawn non-template with the core coloured by the combined indicator and each node coloured by its service's indicator. Louder, more informative, less native. This is the mode that fixes REVIEW.md §3.5 most directly, and it is one click away.

In both modes: **an operational glyph is quiet** (no pip in mode A; teal core in mode B) and a degraded glyph is unmistakable.

### 2.2 State table

| Combined state | Core | Nodes | Pip (mode A) | Motion |
|---|---|---|---|---|
| Operational | filled, `status.operational` | filled | none | M1 ambient breath |
| Minor | filled, `status.minor` | affected node filled with its status colour, others filled base | `status.minor` | M3 on entry |
| Major | filled, `status.major` | as above | `status.major` | M3 on entry |
| Critical | filled, `status.critical` | as above | `status.critical` | **M2 pulse ring**, continuous |
| Unknown | **hollow ring**, `status.unknown` | hollow | `status.unknown` hollow | none |
| Offline | hollow ring, `status.offline`; spokes drop to 40% opacity | hollow | none | none |
| Checking | current state | current | current | **M4 sweep arc**, one pass |

The hollow-ring treatment for unknown is doing real work: it is a shape difference, not just a colour difference, which is what makes the state distinguishable at 16 pt, in monochrome, and to a colourblind user. It is also the direct fix for REVIEW.md §3.4, where `minor` and `unknown` both collapsed to a `?` badge.

### 2.3 Badge

When "show affected count" is on and the count is > 0, a filled disc is drawn at the top-right with the numeral in SF Mono Semibold 8 pt, in the combined status colour with `surface.base` text. Follows the extension's rules exactly: count when non-zero; `!` for major/critical with a zero count; `?` for minor-with-zero and for unknown; nothing when operational (specs.md FR-12).

### 2.4 SwiftUI shape

```swift
struct VibeHub: Shape {
    var nodeScale: CGFloat = 1        // animatable — drives M3's spoke/node spring
    var coreScale: CGFloat = 1        // animatable — drives M1's breath

    func path(in rect: CGRect) -> Path {
        let g = VibeHubGeometry.self
        let side = min(rect.width, rect.height)
        let box  = CGRect(x: rect.midX - side/2, y: rect.midY - side/2,
                          width: side, height: side)
        let c = CGPoint(x: box.midX, y: box.midY)

        var p = Path()
        for i in 0..<4 {
            let n = g.node(i, in: box)
            let v = CGVector(dx: n.x - c.x, dy: n.y - c.y)
            let len = hypot(v.dx, v.dy)
            let u = CGVector(dx: v.dx/len, dy: v.dy/len)
            let from = CGPoint(x: c.x + u.dx * (g.coreRadius + g.gap) * side,
                               y: c.y + u.dy * (g.coreRadius + g.gap) * side)
            let to   = CGPoint(x: n.x - u.dx * (g.nodeRadius + g.gap) * side,
                               y: n.y - u.dy * (g.nodeRadius + g.gap) * side)
            p.move(to: from); p.addLine(to: to)
        }
        // Spokes are stroked by the caller so width can animate independently
        // of the discs; discs are appended as filled sub-paths.
        var stroked = p.strokedPath(.init(lineWidth: g.spokeWidth * side, lineCap: .round))
        for i in 0..<4 {
            let n = g.node(i, in: box)
            let r = g.nodeRadius * side * nodeScale
            stroked.addEllipse(in: CGRect(x: n.x-r, y: n.y-r, width: 2*r, height: 2*r))
        }
        let cr = g.coreRadius * side * coreScale
        stroked.addEllipse(in: CGRect(x: c.x-cr, y: c.y-cr, width: 2*cr, height: 2*cr))
        return stroked
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(nodeScale, coreScale) }
        set { nodeScale = newValue.first; coreScale = newValue.second }
    }
}
```

For per-node colouring (mode B) the view composes four `Circle()`s over a spokes-only `VibeHub`, rather than trying to colour sub-paths of one shape.

### 2.5 NSImage renderer

`NSStatusItem` needs an `NSImage`, and animation in the menu bar means **re-rendering frames**, not attaching a SwiftUI animation. The renderer is therefore explicit:

```swift
enum VibeIconRenderer {
    /// Renders one frame. `phase` ∈ [0,1) drives M1/M2/M4; static states pass 0.
    static func image(for state: IconState, phase: CGFloat = 0) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(state, phase: phase, in: rect)
            return true
        }
        image.isTemplate = state.style.isMonochrome && !state.hasPip
        return image
    }
}
```

- A `CADisplayLink`-backed ticker drives `phase` **only** when an animated state is active, and only while the display is awake and the app is not hidden.
- The breath (M1) runs at 30 fps for 6 s per cycle; the critical pulse (M2) at 30 fps, 1.4 s per cycle. Both are cheap: a 18×18 pt redraw is measured in microseconds. Both stop dead at Motion.off.
- Frames for the small number of static states are cached by `IconState` so a steady app does zero drawing.

### 2.6 Legibility checklist

Every glyph must be verified at: 1× and 2× scale; light and dark menu bars; **against the macOS 26 transparent menu bar over both a light and a busy wallpaper**; in the notch-crowded reduced menu bar; under Increase Contrast; and with the menu bar auto-hidden and revealed over full-screen content. Snapshot tests cover the first four (ARCHITECTURE.md §10).

---

## 3. Icon styles (Appearance setting)

| Style | Mark | For |
|---|---|---|
| **Hub** (default) | The four-spoke hub above | The full readout |
| **Pulse** | A 5-segment ECG-style trace across an 18×10 field. Flat when healthy; the trace spikes, with amplitude by severity, when not. Animated as a slow left-to-right scan at Full motion | People who want a monitor to *look* like a monitor |
| **Minimal** | A single 7 pt disc: filled when operational, ringed when degraded (ring thickness by severity), hollow when unknown | People who want their menu bar back |

All three share the same state table (§2.2), the same pip and badge rules, and the same two rendering modes.

---

## 4. App icon

The app icon is the **six-node** ancestor, kept for brand continuity with the extension, rendered as a proper macOS icon rather than a flat PNG.

### 4.1 Composition

- **Canvas** 1024×1024. macOS squircle: content inset to 824×824 with corner radius 185.4 — the standard grid, so the icon sits correctly beside every other app in the Dock.
- **Background** a radial gradient from `#1B2740` at 35% up-left to `#0A0F18` at the corners, with a 1 px top inner highlight at white 10% and a bottom inner shadow — the dark-instrument feel from the extension icon, with actual depth.
- **Field** a very faint 48 px dot grid at white 3.5%, masked by a radial falloff so it reads only in the corners. Suggests a substrate without becoming a texture.
- **Orbit** two concentric rings at r=0.42 and r=0.47 in `brand.vibe` at 12% and 6%, the outer one dashed.
- **Hub** six spokes at 60° from a bright core. Spokes are a vertical gradient `#22D3EE → #0E7490`, 14 px wide, round caps.
- **Nodes** six discs, r=38 px. **Four of them carry the vendor accents** at the four diagonal positions — Claude amber, GitHub violet, OpenAI green, Gemini blue — and the two on the vertical axis stay cyan. This is the quiet joke in the mark: the four tools you watch, plus the two spokes that make it a hub.
- **Core** r=62 px, `#67E8F9` with a 90 px cyan glow at 45%, and a small specular highlight up-left at white 55%.
- **Lighting** consistent top-left key, matching Apple's convention.

### 4.2 Deliverables

| Asset | Purpose |
|---|---|
| **`VibeStats.icon` (Icon Composer) — the primary and only authored icon** | Layered: `background` / `orbit` / `spokes` / `nodes` / `core` / `glow`. macOS 26 composes the **default, dark, clear, and tinted** appearances from these layers, applies its own specular and shadow treatment, and rasterises every size. Authoring flat PNGs per size is the old workflow and should not be revived |
| Layer discipline for Icon Composer | Background stays a flat gradient with **no** baked highlight or shadow — the system adds both, and a baked one double-lights the icon. The glow layer is a separate blur so the *clear* and *tinted* variants can drop it. The core keeps its own specular only in the default appearance |
| `MenuBarHub.svg`, `MenuBarPulse.svg`, `MenuBarMinimal.svg` | Reference geometry for the renderer; the app draws in code, these are the source of truth for review |
| `docs/assets/*.svg` | The design records checked into this repo |

**Small-size discipline.** At 32 px and 16 px the orbit rings, dot grid, specular highlight, and glow are all dropped; the mark becomes core + six spokes + six nodes on flat `#0E1420`, with spoke width raised to keep the same optical weight. This is drawn as a separate simplified path, not as a naive downscale — a downscaled six-node hub turns into cyan mush at 16 px.

### 4.3 Reference SVGs

Checked in beside this document:

- [`assets/appicon-1024.svg`](assets/appicon-1024.svg) — the full app icon
- [`assets/appicon-32.svg`](assets/appicon-32.svg) — the simplified small variant
- [`assets/menubar-hub.svg`](assets/menubar-hub.svg) — the four-spoke menu bar glyph, all six states in a row

Rendering them to PNG for review:

```bash
# any of these, depending on what's installed
qlmanage -t -s 1024 -o /tmp docs/assets/appicon-1024.svg
# or
rsvg-convert -w 1024 docs/assets/appicon-1024.svg -o /tmp/icon.png
```

---

## 5. Where each mark appears

| Surface | Mark |
|---|---|
| Menu bar | Four-spoke hub (or Pulse / Minimal), 18×18 |
| Popover header | Four-spoke hub, 20 pt, in `brand.vibe`, with the core coloured by combined status |
| Empty / loading state | Four-spoke hub at 64 pt, spokes drawing in sequence |
| Notification icon | App icon (system-supplied, from the `.icon` bundle) |
| About window | App icon at 96 pt |
| Settings toolbar | SF Symbols only — settings should look like macOS, not like the brand |
| DMG background | App icon at 256 pt with an arrow to Applications |
