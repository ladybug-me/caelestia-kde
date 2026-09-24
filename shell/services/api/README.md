# Caelestia QML API

This folder exposes the shell's public QML APIs through the `qs.services.api` module.

Use it like this:

```qml
import qs.services.api

Text {
    text: "Plugins: " + CaelestiaApi.plugins.available.count
}
```

The main entry point is the singleton `CaelestiaApi`.

## API groups

### `CaelestiaApi.plugins`

Source: `PluginsApi.qml`

Provides plugin system access.

```qml
property ListModel available: ListModel {}
```

This is the list of discovered plugins and is used by the loader, plugin store, and plugin page UI.

Typical usage:

```qml
for (let i = 0; i < CaelestiaApi.plugins.available.count; i++) {
    let p = CaelestiaApi.plugins.available.get(i);
    console.log(p.name, p.enabled, p.source);
}
```

## Singleton file

The actual root singleton is defined in `CaelestiaApi.qml`:

```qml
QtObject {
    readonly property PluginsApi plugins: PluginsApi {}
}
```

## Module declaration

The module is registered in `qmldir`:

```text
module qs.services.api
singleton CaelestiaApi 1.0 CaelestiaApi.qml
PluginsApi 1.0 PluginsApi.qml
```

This makes the APIs available anywhere in the shell by importing:

```qml
import qs.services.api
```
