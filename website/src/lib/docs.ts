/**
 * Docs ordering.
 *
 * The order lives here rather than in the loader so the sidebar and the docs
 * index agree without either one asking the other.
 */

export const GROUP_ORDER = ['Getting started', 'Using Caelestia', 'When something breaks', 'Building on it'];

interface Entry {
    id: string;
    data: { group: string; order: number; title: string };
}

export interface Group<T extends Entry> {
    name: string;
    entries: T[];
}

function groupRank(name: string): number {
    const index = GROUP_ORDER.indexOf(name);
    return index === -1 ? GROUP_ORDER.length : index;
}

/** Entries grouped for the sidebar, in reading order. */
export function groupEntries<T extends Entry>(entries: T[]): Group<T>[] {
    const groups = new Map<string, T[]>();

    for (const entry of entries) {
        const list = groups.get(entry.data.group) ?? [];
        list.push(entry);
        groups.set(entry.data.group, list);
    }

    return [...groups.entries()]
        .map(([name, list]) => ({
            name,
            entries: list.sort((a, b) => a.data.order - b.data.order || a.data.title.localeCompare(b.data.title)),
        }))
        .sort((a, b) => groupRank(a.name) - groupRank(b.name) || a.name.localeCompare(b.name));
}
