pragma Singleton

import QtQuick
import qs.utils
import "../../utils/scripts/fzf.js" as Fzf

QtObject {
    id: root

    readonly property list<var> pages: PageDictionary.pages

    property var searchIndex: []
    property var allPages: []
    property var _entriesFinder: null
    property var _pagesFinder: null

    function buildIndex(): void {
        let index = [];
        let indexedPages = [];
        pages.forEach((page, pageIdx) => {
            indexedPages.push({
                page: page,
                pageIdx: pageIdx
            });

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
                    sectionLabel: "",
                    searchText: [setting.label, setting.description, page.label, page.category, keywords].filter(Boolean).join(" ")
                });
            });
        });

        // Every row the pages render, so a setting the dictionary does not name
        // is still findable. A row the dictionary already names keeps the
        // curated entry: it carries hand-written keywords a generated one cannot.
        const named = {};
        index.forEach((entry) => {
            named[`${entry.pageIdx}|${entry.subPageIdx}|${entry.settingLabel.toLowerCase()}`] = true;
        });
        PageRowIndex.rows.forEach((row) => {
            if (named[`${row.pageIdx}|${row.subPageIdx}|${row.label.toLowerCase()}`])
                return;
            const page = pages[row.pageIdx];
            if (!page)
                return;
            index.push({
                settingLabel: row.label,
                settingDescription: row.description || "",
                pageIdx: row.pageIdx,
                subPageIdx: row.subPageIdx,
                pageLabel: page.label,
                pageIcon: page.icon,
                sectionLabel: row.section || "",
                searchText: [row.label, row.description, row.section, page.label, page.category].filter(Boolean).join(" ")
            });
        });

        allPages = indexedPages;
        searchIndex = index;
        _entriesFinder = new Fzf.Finder(searchIndex, {
            selector: e => e.searchText
        });
        _pagesFinder = new Fzf.Finder(allPages, {
            selector: e => [e.page.label, e.page.description, e.page.category].filter(Boolean).join(" ")
        });
    }

    function fuzzyPages(query: string): list<var> {
        const search = query.trim().replace(/\s+/g, " ");
        if (!search)
            return allPages;
        if (!_pagesFinder)
            return [];

        const results = _pagesFinder.find(search);
        results.sort((a, b) => {
            if (a.score === b.score) {
                const aLen = [a.item.page.label, a.item.page.description, a.item.page.category].filter(Boolean).join(" ").length;
                const bLen = [b.item.page.label, b.item.page.description, b.item.page.category].filter(Boolean).join(" ").length;
                return aLen - bLen;
            }
            return b.score - a.score;
        });
        return results.slice(0, 30).map(r => r.item);
    }

    function fuzzyEntries(query: string): list<var> {
        const search = query.trim().replace(/\s+/g, " ");
        if (!search || !_entriesFinder)
            return [];

        const results = _entriesFinder.find(search);
        results.sort((a, b) => {
            if (a.score === b.score)
                return a.item.searchText.trim().length - b.item.searchText.trim().length;
            return b.score - a.score;
        });
        return results.slice(0, 30).map(r => r.item);
    }

    function indexForKey(key: string): int {
        return PageDictionary.pageIdxFor(key);
    }

    function defaultSubPageForKey(key: string): int {
        return PageDictionary.defaultSubPageForKey(key);
    }

    Component.onCompleted: {
        buildIndex();
    }
}
