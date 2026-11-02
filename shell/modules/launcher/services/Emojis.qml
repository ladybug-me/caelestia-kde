pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services

Singleton {
    id: root

    readonly property bool _loaded: EmojiDb.loaded
    readonly property int itemCount: EmojiDb.count
    readonly property var _cache: new Map()

    function wrapItem(item: var): var {
        if (!item || !item.ch)
            return item;
        let cached = root._cache.get(item.ch);
        if (!cached) {
            cached = {
                ch: item.ch,
                name: item.name,
                nameLower: item.nameLower
            };
            root._cache.set(item.ch, cached);
        }
        return cached;
    }

    function reload(): void {
        if (!EmojiDb.loaded) {
            console.warn("EmojiDb not loaded yet");
        }
    }

    function recordUsage(ch: string): void {
        EmojiDb.recordUsage(ch);
    }

    function getSortedItems(): var {
        const favEmojis = GlobalConfig.launcher.favouriteEmojis || [];
        const raw = EmojiDb.getSortedItems(favEmojis, 30);
        return raw.map(root.wrapItem);
    }

    function search(text: string): var {
        const favEmojis = GlobalConfig.launcher.favouriteEmojis || [];
        const raw = EmojiDb.search(text, 30, favEmojis);
        return raw.map(root.wrapItem);
    }

    Connections {
        function onFavouriteEmojisChanged(): void {
        }

        target: GlobalConfig.launcher
    }
}
