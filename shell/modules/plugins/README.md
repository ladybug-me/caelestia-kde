# Bundled Plugins Directory

This directory is for plugins that are fetched from the community plugin store and bundled with the shell.
Plugins in this directory are installed via cmake to `~/.config/quickshell/caelestia/modules/plugins/`.

User-installed plugins (e.g. ones created manually or downloaded from the store UI) should go into `~/.config/caelestia/plugins/`.

## Registering bar widgets

A plugin can add widgets to the taskbar (Nexus → Taskbar → Toggle & rearrange)
by declaring them in its `metadata.json`:

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "type": "quickshell",
  "ui": "main.qml",
  "barWidgets": [
    {
      "id": "myWidget",
      "name": "My widget",
      "icon": "star",
      "defaultZone": "right",
      "component": "BarWidget.qml"
    }
  ]
}
```

Fields per widget:

| Field | Required | Description |
| --- | --- | --- |
| `id` | yes | Unique widget id. Must not collide with a built-in id (built-ins win). |
| `component` | yes | QML file **relative to the plugin folder**. Absolute paths and `..` are rejected. |
| `popout` | no | QML file **relative to the plugin folder**, rendered in the shell's sliding popout container. Same rules as `component`. Defaults to none. |
| `name` | no | Label shown in the editor. Defaults to `id`. |
| `icon` | no | Material icon name shown in the editor. Defaults to `widgets`. |
| `defaultZone` | no | `left`, `middle` or `right`. Defaults to `right`. |
| `available` | no | Whether the widget is usable. Defaults to `true`. |
| `unavailableText` | no | Reason shown when `available` is `false`. |

Once registered, the widget:

- shows up in the Toggle & rearrange page (disable, move between zones);
- renders in the bar (the bar shows it only while the entry is enabled);
- can open a hover popout by exposing a
  `handleHover(pos, isHorizontal, popouts)` function on its root item;
- can react to scroll events sent through the bar by exposing a
  `handleWheel(pos, isHorizontal, angleDelta)` function on its root item;
- can render a popout in the shell's sliding container: declare `popout` and
  set `popouts.currentName` to the widget's `id` to reveal it.

A widget is handed the ambient values the built-ins get, for the ones its root
declares: `bar`, `screen`, `visibilities` and `popouts`. Anything left out is
not touched.

| Property | Description |
| --- | --- |
| `bar` | The bar the widget is rendered in. |
| `screen` | The screen that bar belongs to. |
| `visibilities` | Which drawers and panels are currently visible. |
| `popouts` | The popout state, so the widget can open a popout. |

Widgets are registered when the plugin loads and unregistered when it is
disabled or removed, so no shell restart is needed after toggling the plugin.

## Registering background widgets

A plugin can add items to the desktop background layer by declaring them in its
`metadata.json` under `backgroundWidgets`:

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "type": "quickshell",
  "backgroundWidgets": [
    {
      "id": "myDesktopWidget",
      "name": "My Desktop Widget",
      "component": "DesktopWidget.qml",
      "z": 2.5
    }
  ]
}
```

Fields per widget:

| Field | Required | Description |
| --- | --- | --- |
| `id` | yes | Unique widget id. |
| `component` | yes | QML file **relative to the plugin folder**. Absolute paths and `..` are rejected. |
| `name` | no | Label for the widget. Defaults to `id`. |
| `z` | no | Z-stacking order inside `Background.qml` (defaults to `2.5`, between wallpaper/visualiser and desktop icons). |

A background widget is instantiated as a child inside `Background.qml` per active screen and is handed ambient values for whichever properties its root declares: `screen`, `modelData`, and `background`.

## Plugin settings

A plugin can declare the settings the shell should offer next to it in the Plugins page, under the `settings` field of its manifest:

```json
{
  "id": "my-plugin",
  "settings": [
    { "id": "fancy", "label": "Fancy mode", "type": "toggle", "default": false },
    { "id": "greeting", "label": "Greeting", "type": "text", "default": "hello", "placeholder": "Say hello" },
    { "id": "size", "label": "Icon size", "type": "number", "default": 3, "min": 1, "max": 10, "step": 1 },
    { "id": "mode", "label": "Mode", "type": "enum", "options": ["compact", "full"], "default": "compact" }
  ]
}
```

| Field | Required | Description |
| --- | --- | --- |
| `id` | yes | Setting id, used as the key the value is stored under. |
| `label` | yes | Label shown next to the control. |
| `type` | yes | `toggle`, `text`, `number` or `enum`. |
| `default` | no | Value used until another one is picked. |
| `options` | `enum` only | Values the user can choose from. |
| `min`, `max`, `step` | `number` only | Bounds and increment of the spin box. Default to `0`, `100` and `1`. |
| `placeholder` | `text` only | Hint shown while the field is empty. |

Rows of an unknown type are not rendered, so a manifest can carry settings a newer shell understands. The button that opens the settings is only shown for plugins that declare at least one.

Values are stored with Qt's `Settings` under the `Plugin_<plugin id>` category, so a plugin reads the ones it declares back with:

```qml
Settings {
    category: "Plugin_my-plugin"
}
```
