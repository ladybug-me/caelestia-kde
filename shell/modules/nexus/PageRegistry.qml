pragma Singleton

import QtQuick
import qs.utils
import "../../utils/scripts/fzf.js" as Fzf

QtObject {
    id: root

    readonly property list<var> pages: PageDictionary.pages

    property var searchIndex: []

    function buildIndex() {
        let index = [];
        pages.forEach((page, pageIdx) => {
            index.push({
                settingLabel: page.label,
                settingDescription: page.description || "",
                pageIdx: pageIdx,
                subPageIdx: -1,
                pageLabel: qsTr("Main Page"),
                pageIcon: page.icon,
                searchText: [page.label, page.description, page.category].filter(Boolean).join(" ")
            });

            if (!page.settings) return;
            page.settings.forEach((setting) => {
                const keywords = setting.keywords ? setting.keywords.join(" ") : "";
                index.push({
                    settingLabel: setting.label,
                    settingDescription: setting.description || "",
                    pageIdx: pageIdx,
                    subPageIdx: setting.subPageIdx !== undefined ? setting.subPageIdx : -1,
                    pageLabel: page.label,
                    pageIcon: page.icon,
                    searchText: [setting.label, setting.description, page.label, page.category, keywords].filter(Boolean).join(" ")
                });
            });
        });
        searchIndex = index;
    }

    Component.onCompleted: {
        buildIndex();
    }

    function fuzzyPages(query: string): list<var> {
        const indexed = pages.map((page, pageIdx) => ({
            page,
            pageIdx
        }));

        const search = query.trim().replace(/\s+/g, " ");
        if (!search)
            return indexed;

        const selector = e => [e.page.label, e.page.description, e.page.category].filter(Boolean).join(" ");
        const finder = new Fzf.Finder(indexed, {
            selector
        });
        return finder.find(search).sort((a, b) => {
            if (a.score === b.score)
                return selector(a.item).trim().length - selector(b.item).trim().length;
            return b.score - a.score;
        }).map(r => r.item);
    }

    function fuzzyEntries(query: string): list<var> {
        const search = query.trim().replace(/\s+/g, " ");
        if (!search)
            return [];

        const selector = e => e.searchText;
        const finder = new Fzf.Finder(searchIndex, {
            selector
        });
        return finder.find(search).sort((a, b) => {
            if (a.score === b.score)
                return selector(a.item).trim().length - selector(b.item).trim().length;
            return b.score - a.score;
        }).map(r => r.item);
    }

    function indexForKey(key: string): int {
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].key === key) return i;
        }
        return -1;
    }
}
