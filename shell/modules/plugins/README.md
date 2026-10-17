# Bundled Plugins Directory

This directory is for plugins that are fetched from the community plugin store and bundled with the shell.
Plugins in this directory are installed via cmake to `~/.config/quickshell/caelestia/modules/plugins/`.

User-installed plugins (e.g. ones created manually or downloaded from the store UI) should go into `~/.config/caelestia/plugins/`.

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
