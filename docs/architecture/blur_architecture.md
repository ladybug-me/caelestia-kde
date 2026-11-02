# Blur architecture

How KWin background blur works in Caelestia, and how to add it to a new panel.

---

## Overview

Caelestia uses KWin's native background-blur effect, exposed through Quickshell's
`BackgroundEffect.blurRegion`. Rather than blurring the whole layer-shell window, it
registers a set of **Wayland surface regions** that KWin blurs behind. Every panel that
wants blur must register its on-screen rectangle in that region, and keep it in sync as
the panel moves or resizes.

`BlurMask` (in `shell/modules/drawers/blur/`) is the component that owns this
responsibility for a single panel. It lives in `ContentWindow`'s region tree.

---

## Components

### `BackgroundEffect.blurRegion` (`ContentWindow.qml`)

The root `StyledWindow` sets `BackgroundEffect.blurRegion` to a combined `Region`
tree. This is the single Wayland protocol surface sent to KWin. Everything else is
additive.

```qml
BackgroundEffect.blurRegion: Region {
    // static baseline + bar strips + border-rounding corners …
    BlurMask { target: bar; … }
    BlurMask { target: panels.launcher; … }
    BlurMask { target: panels.notifications; … }
    …
}
```

### `BlurMask` (`shell/modules/drawers/blur/BlurMask.qml`)

A `Region` subtype that wraps three helpers:

| Helper | Job |
|---|---|
| `BlurOffsets` | Computes the panel's on-screen rect, accounting for `blurOffset*`, deform matrix, and per-edge radii (`rTop`, `rBottom`, `rLeft`, `rRight`) |
| `BlurBodies` | Emits the main rectangular cross region (`bX`, `bY`, `bW`, `bH`) bounded by `inLeft`, `inRight`, `inTop`, `inBottom` |
| `BlurCorners` | Emits stepped horizontal rectangular strip regions approximating quarter-circle rounded corners when `blurMask` is enabled |

**Required properties:**

| Property | Source |
|---|---|
| `target` | The `Item` to blur behind (set to `null` when hidden) |
| `contentItem` | `root.contentItem` — the layer shell's surface item |
| `blurOffsetTop/Bottom/Left/Right` | `root.blurOffset*` — per-edge crop for the bar border |

**Optional properties** (pulled from `target` automatically if present):

| Property | Default | Usage |
|---|---|---|
| `vAnchor` | `"bottom"` | `"top"`, `"bottom"`, `"both"`, or `"none"` |
| `hAnchor` | `"right"` | `"left"`, `"right"`, `"both"`, or `"none"` |
| `offsetScale` | `0` | Fraction of the panel's slide-in animation offset already applied |
| `deformMatrix` | identity | Transform applied by a `BlobRect` background shape |

> [!NOTE]
> `vAnchor` and `hAnchor` default to `"bottom"` and `"right"` if omitted on both `target` and `BlurMask`.
> For floating panels or menus that need rounded corners, you must explicitly set `vAnchor` and `hAnchor` to `"none"` or the appropriate seam anchor.

Setting `target: null` when the panel is closed is important — it collapses the
region to zero so KWin stops blurring that area immediately.

---

## How to add blur to a new panel

### 1. Expose the panel item

`BlurMask.target` must be the concrete `Item` whose on-screen bounds KWin blurs.
If that item is internal to a component, expose it via a `readonly property alias`.

```qml
// MyPanel.qml
Item {
    id: root
    readonly property alias panelItem: card   // ← expose the inner rect

    Rectangle {
        id: card
        // … panel visuals …
    }
}
```

This mirrors the pattern `Controls.Menu` uses for `backgroundItem`.

### 2. Register a `BlurMask` in `ContentWindow.qml`

Inside the existing `BackgroundEffect.blurRegion` block, add one entry:

```qml
BlurMask {
    target: myPanel.visible ? myPanel.panelItem : null
    contentItem: root.contentItem
    blurOffsetTop:    root.blurOffsetTop
    blurOffsetBottom: root.blurOffsetBottom
    blurOffsetLeft:   root.blurOffsetLeft
    blurOffsetRight:  root.blurOffsetRight
}
```

- For **docked panels sliding from an edge**: Set the edge anchor (e.g. `hAnchor: "left"` for a left-docked sidebar).
- For **floating popups / menus with 4 rounded corners** (like `Controls.Menu`): Set `vAnchor: "none"` and `hAnchor: "none"` on the target (or pass to `BlurMask`).
- For **seamed panels / submenus**: Set `vAnchor: "none"` and `hAnchor: opensRight ? "left" : "right"`. This squares off the shared seam while rounding the outer corners.
- Add `deformMatrix: myPanelBg.deformMatrix` if the panel uses a `BlobRect` background (for animated wave-deform shape panels).

### 3. Verify

Run `verify_qml_conventions` on modified files. The blur region updates live
with no build step needed.

---

## `vAnchor` / `hAnchor` & corner rounding reference

Corner radii in `BlurOffsets` are determined by:
- `rTop`: `(!isIsland && (vAnchor === "top" || vAnchor === "both")) ? 0 : r`
- `rBottom`: `(!isIsland && (vAnchor === "bottom" || vAnchor === "both")) ? 0 : r`
- `rLeft`: `(!isIsland && (hAnchor === "left" || hAnchor === "both")) ? 0 : r`
- `rRight`: `(!isIsland && (hAnchor === "right" || hAnchor === "both")) ? 0 : r`

Corner radii in `BlurCorners` are then computed as:
- Top-Left: `rTL = Math.min(rTop, rLeft)`
- Top-Right: `rTR = Math.min(rTop, rRight)`
- Bottom-Left: `rBL = Math.min(rBottom, rLeft)`
- Bottom-Right: `rBR = Math.min(rBottom, rRight)`

| Panel type | `vAnchor` | `hAnchor` | Resulting corner rounding |
|---|---|---|---|
| Top bar | `"top"` | `"both"` | Top, left, and right squared; bottom corners rounded |
| Bottom bar | `"bottom"` | `"both"` | Bottom, left, and right squared; top corners rounded |
| Left sidebar | `"both"` | `"left"` | Top, bottom, and left squared; right corners rounded |
| Right sidebar | `"both"` | `"right"` | Top, bottom, and right squared; left corners rounded |
| Overview (full-screen) | `"both"` | `"both"` | All 4 edges squared (no rounded corners) |
| Floating popup / menu | `"none"` | `"none"` | All 4 corners rounded (`rTL`, `rTR`, `rBL`, `rBR` = `r`) |
| Seamed submenu (opens right) | `"none"` | `"left"` | Left seam squared (`rTL=0, rBL=0`); outer right corners rounded (`rTR=r, rBR=r`) |
| Seamed submenu (opens left) | `"none"` | `"right"` | Right seam squared (`rTR=0, rBR=0`); outer left corners rounded (`rTL=r, rBL=r`) |

---

## How rounded blur masks work

Wayland protocol surfaces (`wl_region`) only accept collections of axis-aligned rectangles. To produce smooth rounded corners behind curved surfaces, `shell/modules/drawers/blur/` decomposes the panel into two cooperative components:

1. **`BlurBodies.qml` (Core cross regions)**:
   Emits two overlapping central rectangles that cover the core area without protruding into the rounded corner spaces:
   - Horizontal cross: spans `x: bX` to `bX + bW`, `y: inTop` to `inBottom`
   - Vertical cross: spans `x: inLeft` to `inRight`, `y: bY` to `bY + bH`
   Here `inLeft = bX + rLeft`, `inRight = bX + bW - rRight`, `inTop = bY + rTop`, and `inBottom = bY + bH - rBottom`. When an edge radius is `0`, the body region extends all the way to that edge without any inset.

2. **`BlurCorners.qml` (Discretized quarter-circle slices)**:
   For each corner where the effective radius is non-zero (`rTL`, `rTR`, `rBL`, `rBR`), it generates up to 100 horizontal strip `Region` elements based on the circle formula $x = r \cdot \sqrt{1 - (y/r)^2}$. The number of active strip slices is controlled by `blurSettings.blurQuality`.

When `GlobalConfig.appearance.blurMask` is disabled, `BlurMask` falls back to a single flat bounding rectangle covering `(tX, tY, tW, tH)`.

When `GlobalConfig.appearance.islands` is enabled, edge anchors do not collapse `rTop`/`rBottom`/`rLeft`/`rRight` to zero, allowing floating island panels to retain rounded corners along screen boundaries.

---

## Config guards

`BlurMask` and `BlurCorners` internally respect `GlobalConfig.appearance.blur` and
`GlobalConfig.appearance.blurMask`. You do **not** need to wrap your `BlurMask` in
a condition — when the user disables blur the component emits zero-sized regions
automatically.

---

## Files

| File | Role |
|---|---|
| [`shell/modules/drawers/ContentWindow.qml`](../../shell/modules/drawers/ContentWindow.qml) | Hosts all `BlurMask` entries inside `BackgroundEffect.blurRegion` |
| [`shell/modules/drawers/blur/BlurMask.qml`](../../shell/modules/drawers/blur/BlurMask.qml) | Per-panel blur region component |
| [`shell/modules/drawers/blur/BlurOffsets.qml`](../../shell/modules/drawers/blur/BlurOffsets.qml) | Geometry computation |
| [`shell/modules/drawers/blur/BlurBodies.qml`](../../shell/modules/drawers/blur/BlurBodies.qml) | Main rectangular region |
| [`shell/modules/drawers/blur/BlurCorners.qml`](../../shell/modules/drawers/blur/BlurCorners.qml) | Rounded-corner mask regions |
