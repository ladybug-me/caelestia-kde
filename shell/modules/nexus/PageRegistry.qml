pragma Singleton

import QtQuick
import qs.utils
import "../../utils/scripts/fzf.js" as Fzf
import qs.modules.nexus

QtObject {
    id: root

    readonly property int updatesPageIdx: Math.max(0, PageCompRegistry.categoryIdxForKey("updates"))
    readonly property var pages: PageCompRegistry.categories

    property var searchIndex: []
    property var allPages: []
    property var _entriesFinder: null
    property var _pagesFinder: null

    function buildIndex(): void {
        let index = [];
        let indexedPages = [];
        const categories = PageCompRegistry.categories;

        for (let catIdx = 0; catIdx < categories.length; catIdx++) {
            const cat = categories[catIdx];
            indexedPages.push({
                page: cat,
                pageIdx: cat.categoryIdx
            });

            index.push({
                settingLabel: cat.label,
                settingDescription: cat.description || "",
                pageIdx: cat.categoryIdx,
                subPage: "hub",
                pageLabel: qsTr("Main Page"),
                pageIcon: cat.icon,
                searchText: [cat.label, cat.description, cat.key].filter(Boolean).join(" ")
            });

            const pages = cat.pages || [];
            for (let pIdx = 0; pIdx < pages.length; pIdx++) {
                const page = pages[pIdx];
                const pageKeywords = (page.keywords || []).join(" ");

                index.push({
                    settingLabel: page.label,
                    settingDescription: page.description || page.status || "",
                    pageIdx: cat.categoryIdx,
                    subPage: page.key,
                    pageLabel: cat.label,
                    pageIcon: cat.icon,
                    sectionLabel: page.section || "",
                    searchText: [page.label, page.description, page.status, cat.label, pageKeywords].filter(Boolean).join(" ")
                });

                const subs = page.subPages || [];
                for (let sIdx = 0; sIdx < subs.length; sIdx++) {
                    const sub = subs[sIdx];
                    const subKeywords = (sub.keywords || []).join(" ");

                    index.push({
                        settingLabel: sub.label,
                        settingDescription: "",
                        pageIdx: cat.categoryIdx,
                        subPage: sub.key,
                        pageLabel: cat.label,
                        pageIcon: cat.icon,
                        sectionLabel: page.label,
                        searchText: [sub.label, page.label, cat.label, subKeywords].filter(Boolean).join(" ")
                    });
                }
            }
        }

        const named = {};
        for (let i = 0; i < index.length; i++) {
            const entry = index[i];
            named[`${entry.pageIdx}|${entry.subPage}|${entry.settingLabel.toLowerCase()}`] = true;
        }

        PageRowIndex.rows.forEach(row => {
            if (named[`${row.pageIdx}|${row.subPage}|${row.label.toLowerCase()}`])
                return;
            const cat = categories[row.pageIdx];
            if (!cat)
                return;
            index.push({
                settingLabel: row.label,
                settingDescription: row.description || "",
                pageIdx: row.pageIdx,
                subPage: row.subPage,
                pageLabel: cat.label,
                pageIcon: cat.icon,
                sectionLabel: row.section || "",
                searchText: [row.label, row.description, row.section, cat.label].filter(Boolean).join(" ")
            });
        });

        allPages = indexedPages;
        searchIndex = index;
        _entriesFinder = new Fzf.Finder(searchIndex, {
            selector: e => e.searchText
        });
        _pagesFinder = new Fzf.Finder(allPages, {
            selector: e => [e.page.label, e.page.description, e.page.key].filter(Boolean).join(" ")
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
                const aLen = [a.item.page.label, a.item.page.description, a.item.page.key].filter(Boolean).join(" ").length;
                const bLen = [b.item.page.label, b.item.page.description, b.item.page.key].filter(Boolean).join(" ").length;
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
        return PageCompRegistry.categoryIdxForKey(key);
    }

    function defaultSubPageForKey(key: string): string {
        return PageCompRegistry.defaultPageForCategoryKey(key);
    }

    Component.onCompleted: {
        buildIndex();
    }
}
