pragma Singleton

import QtQuick

QtObject {
    id: root

    // Background widgets declared by plugins through their metadata.json `backgroundWidgets`
    // field. Each entry is normalised to:
    // { id, name, z, componentUrl, pluginId }
    property var widgets: []

    // Bumped on every change of `widgets`. Desktops follow it to reload their
    // widget loaders, since a Repeater bound to a plain array keeps its delegates.
    property int revision: 0

    // Copy of `widgets` whose identity changes with `revision`, so a Repeater
    // rebuilds its delegates instead of keeping the ones of the previous list.
    readonly property var widgetList: {
        root.revision;
        return root.widgets.slice();
    }

    readonly property var byId: {
        const map = {};
        for (const widget of root.widgets)
            map[widget.id] = widget;
        return map;
    }

    function widget(id: string): var {
        return root.byId[id] ?? null;
    }

    function isKnown(id: string): bool {
        return root.byId[id] !== undefined;
    }

    // Replaces every widget previously registered by this plugin, so a reload
    // never leaves stale components behind.
    function register(pluginId: string, specs: var): void {
        const next = root.widgets.filter(widget => widget.pluginId !== pluginId);
        for (const spec of (specs ?? []))
            next.push(Object.assign({ pluginId: pluginId }, spec));
        root.widgets = next;
        root.revision++;
    }

    function unregister(pluginId: string): void {
        root.widgets = root.widgets.filter(widget => widget.pluginId !== pluginId);
        root.revision++;
    }

    function clear(): void {
        root.widgets = [];
        root.revision++;
    }
}
