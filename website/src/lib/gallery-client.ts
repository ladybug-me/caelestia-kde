/**
 * The gallery's entry point.
 *
 * Each demo is wired only if its root is on the page, so the modules are shared
 * rather than duplicated per route, and a page that shows one demo does not pay
 * for the others' setup.
 */

import { initBarDemo } from './demos/bar';
import { initLauncherDemo } from './demos/launcher';
import { initNotificationsDemo } from './demos/notifications';
import { initWorkspacesDemo } from './demos/workspaces';

type Cleanup = () => void;

const demos: Array<[string, (root: HTMLElement) => Cleanup]> = [
    ['[data-demo="bar"]', initBarDemo],
    ['[data-demo="notifications"]', initNotificationsDemo],
    ['[data-demo="launcher"]', initLauncherDemo],
    ['[data-demo="workspaces"]', initWorkspacesDemo],
];

function start(): void {
    const cleanups: Cleanup[] = [];

    for (const [selector, init] of demos) {
        for (const root of document.querySelectorAll<HTMLElement>(selector)) {
            cleanups.push(init(root));
        }
    }

    // Astro's client router keeps the page alive across navigations; tearing the
    // listeners down is what stops the same pointer drag being wired twice.
    document.addEventListener('astro:before-swap', () => {
        cleanups.splice(0).forEach((cleanup) => cleanup());
    });
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
} else {
    start();
}
