# Bar panels architecture

This document provides a simplified overview of how the Caelestia extra bar panels work, from the backend C++ settings node to the QML frontend that draws them around the frame.

---

## 1. High-Level Overview

```text
[ Nexus (Extra bars page, Taskbar page) ]
              │ edits
              ▼
[ GlobalConfig.bar.panels (BarPanelList) ]
              │
              ▼
[ PanelLayer.qml ]
  screenPanels ──▶ panelRects ──▶ Repeater (one Bar per panel)
              │                        │
              │                        ├── islands / bands drawn over the frame
              │                        ├── strips handed to the mask and the blur
              │                        └── popouts grown from the panel's edge
              ▼
[ ContentWindow.qml ]
  frameEdges ──▶ masks, blur corners, drawer insets
              ▼
[ Exclusions.qml ]
  full-edge panels reserve space for tiled windows
```

- **`BarPanel`**: One extra bar, as a settings node.
- **`PanelLayer.qml`**: Owns the panels of one screen: where they sit, how thick the frame gets, which strips the compositor reads, and the pointer routing the layer exposes.
- **`Exclusions.qml`**: Reserves the space a full-edge panel takes, so windows are not tiled under it.
- **`ExtraBarsPanel.qml`** / **`TaskbarPanel.qml`**: The Nexus pages that edit the list.

---

## 2. Core Components

### `BarPanel`

A single extra bar. Declared in `shell/plugin/src/Caelestia/Config/barconfig.hpp` as a `settings::ObjectNode`, so every field is a live property.

**Key fields:**

- **`name`**: Shown in the Nexus pages and in the components page title.
- **`enabled`**: A disabled panel is not drawn and reserves nothing.
- **`position`**: `top`, `bottom`, `left` or `right`.
- **`screens`**: Regex list matched against the screen name. Empty means every screen.
- **`lengthPercent`**: How much of the edge the panel spans. `100` (the default) makes it a full-edge panel; less makes it an island.
- **`align`**: Where a partial panel sits along its edge (`start`, `center`, `end`).
- **`persistent`**: Whether the panel stays on screen. When it is off, the panel waits at its edge and comes out on hover or on a drag.
- **`showOnHover`**: With `persistent` off, whether the pointer reveals the panel or it has to be dragged open.
- **`entries`**: The widget list for that bar. It is separate from `bar.entries`, so each panel can show different widgets.

### `BarPanelList`

The global list, exposed as `GlobalConfig.bar.panels`. In QML it is read with `.count`, `.at(i)` and `.values`, and edited with `.insert({...})` and `.remove(i)`. Panels are global, not per screen: a panel selects the screens it applies to through `screens`.

### `PanelLayer.qml`

The desktop window of each screen instantiates one layer inside its pointer interactions, so the panels share the window's layer surface, border, islands and input mask.

**From the list to rectangles:**

1. **`screenPanels`** filters the list: enabled panels whose `screens` match this screen, using `Strings.testRegexList`.
2. **`panelRects`** places each one. A full-edge panel spans the usable edge (the window minus `panelInset` on both sides); a partial one takes `lengthPercent` of it and is aligned by `align`. `panelInset` is the island spacing when islands are on, and zero otherwise, so a panel does not merge with the frame.
3. The band repeater draws them.

Each band instantiates the same `Bar` the primary bar uses, with `entries` bound to its own panel, so widgets, spacing and popouts behave identically anywhere on the frame.

**What the layer exposes:**

- **`thickness`**: The bar's own thickness, which is also a panel's.
- **`edges`** / **`reservations`** / **`frameEdges`**: `FrameEdges` values. `edges` is the panel thickness per side right now, `reservations` the space a panel keeps, and `frameEdges` the final frame thickness per side: the larger of the bar, the border and the panel. Nothing else recomputes it.
- **`strips`**: One `Region` per partial panel, snapped to where the band rests. The input mask subtracts them and the background blur adds them, so no fixed number of panels is baked into either.
- **`bands`**: The live bands, for the islands that follow them while they slide.
- **`bandAt(x, y)`**, **`resetHover()`**, **`updateReveal(...)`**, **`clearReveal()`**: Pointer routing, mirroring what the single bar does.
- **`thicknessOn(edge)`**, **`takesSpaceOn(edge)`**: Where `edges` and `reservations` come from.

### `FrameEdges.qml`

A four-value holder (`left`, `right`, `top`, `bottom`) with no behaviour. It is the type of every per-side thickness that crosses a file boundary.

### `Exclusions.qml`

Panels that span a full edge thicken the frame, so the exclusion zones grow with them.

- **`reservations`**: Per-side space handed down by the window (`PanelLayer` thickness where a panel takes space, zero elsewhere; partial panels never reserve).
- **`leftExclusion`** / **`topExclusion`** / **`rightExclusion`** / **`bottomExclusion`**: `Math.max` of the bar or border and the reservation on that side.
- **`usableWidth`** / **`usableHeight`** / **`usableArea`**: Derived from those exclusions and used by the tiling integration.

### `Panels.qml` and popouts

A popout opened from a panel has to grow from that panel's edge, not from the main bar's. The origin is written in one call, `popouts.setOrigin(edge, inset, panelIndex)`, by whichever bar or band is opening it; `PopoutState` holds the three values together and derives `isHorizontal` from the edge, so an edge and its inset can never go out of step. That indirection is why the same `Bar` component works unchanged on any edge.

---

## 3. Placement, Space and Reveal

- **Full-edge versus partial**: `lengthPercent` at `100` means the panel merges with the frame and reserves space. Anything below makes an island that floats over the desktop and reserves nothing.
- **Persistent panels** (the default) stay on screen and keep their space.
- **Hover panels** (`persistent: false`, `showOnHover: true`) slide out while the pointer is on the strip they keep at their edge.
- **Drag panels** (`persistent: false`, `showOnHover: false`) are pulled open by dragging inwards past `Config.bar.dragThreshold`, and closed by dragging back out.
- **Collapse**: every panel hides while the overview is open or a window is fullscreen, exactly like the frame and the main bar (`panelsVisible`).

---

## 4. Nexus

### Extra bars page

`shell/modules/nexus/pages/panels/ExtraBarsPanel.qml` lists every bar of the shell: the main bar as **Bar 1**, then the extra panels. Picking a panel edits it: name, edge, position, alignment, length, screens and the two reveal switches. Adding one inserts a node and selects it.

An edge holds one bar. The main bar keeps its own edge, and "Add bar" only offers the edges that are still free, so two bars never draw over each other. A new panel spans its whole edge; `lengthPercent` is how it is turned into an island.

Every row has a **Widgets of this bar** button, which opens the components page with that bar as the target, stacked on top of the extra bars list so Back returns to it.

### Taskbar page

`shell/modules/nexus/pages/panels/TaskbarPanel.qml` is the entry point for the main bar. It resets the target to `-1` before opening the components page, so entering from here never edits a panel selected earlier.

### Components page

`shell/modules/nexus/pages/panels/taskbar/BarComponents.qml` edits the widgets of one bar. The target lives in `NexusState.barComponentsTarget`: `-1` is the primary bar, anything else indexes `GlobalConfig.bar.panels`.

- **`targetNode`**: The settings node being edited (`GlobalConfig.bar` or the selected panel).
- **`barName`**: Shown in the page title, so it is clear which bar is being changed.
- **Load, reset and replace**: Every read and write goes through `targetNode`, so the page works the same for the main bar and for any panel.

### Opening the editor from a bar

Right clicking the empty space of a bar opens a `barcontext` popout, which calls `WindowFactory.openBarComponents(target)`. That call owns the page indices and pushes the extra bars list under the editor, so no page has to carry a "where did I come from" flag.

---

## 5. Important Files

| File | Purpose |
|---|---|
| `plugin/src/Caelestia/Config/barconfig.hpp` | `BarPanel` node and the global `panels` list. |
| `modules/drawers/PanelLayer.qml` | Filters, places and draws the panels; routes pointer, popouts and frame thickness. |
| `modules/drawers/FrameEdges.qml` | The per-side thickness value passed between the window, the panels and the exclusions. |
| `modules/drawers/ContentWindow.qml` | Owns the window; asks the panel layer for the frame edges and the strips. |
| `modules/drawers/Exclusions.qml` | Reserves the space full-edge panels take. |
| `modules/drawers/Panels.qml` | Popouts and panels of the window, shared by bar and extra panels. |
| `modules/nexus/pages/panels/ExtraBarsPanel.qml` | Nexus page to add and edit panels. |
| `modules/nexus/pages/panels/taskbar/BarComponents.qml` | Widget editor, now targeting any bar. |
| `modules/nexus/WindowFactory.qml` | `openBarComponents(target)`: the one place that knows the editor's page indices. |
| `modules/nexus/NexusState.qml` | `barComponentsTarget` and the sub-page navigation. |
| `tests/test_bar_panels.sh` | Structural tests for the panel wiring. |
