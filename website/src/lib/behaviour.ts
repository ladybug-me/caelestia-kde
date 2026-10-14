/**
 * The site's shared client behaviour: the doc-scoped niceties, not the demos.
 *
 * Everything here is additive. The pages read and navigate without JavaScript;
 * this adds the reveal, the copy buttons and the palette controls on top.
 */

import { PALETTE_EVENT, getState, setMode, setPalette, type PaletteState } from './palette-store';

/** Reveal on scroll. Elements are visible by default; this only animates them. */
function initReveals(): void {
    const targets = document.querySelectorAll<HTMLElement>('.reveal');
    if (targets.length === 0) return;

    if (!('IntersectionObserver' in window)) {
        targets.forEach((target) => target.classList.add('is-in'));
        return;
    }

    const observer = new IntersectionObserver(
        (entries) => {
            for (const entry of entries) {
                if (!entry.isIntersecting) continue;
                entry.target.classList.add('is-in');
                observer.unobserve(entry.target);
            }
        },
        { rootMargin: '0px 0px -8% 0px', threshold: 0.05 },
    );

    targets.forEach((target) => observer.observe(target));
}

/**
 * Copy buttons. The label changes for two seconds and a live region says so,
 * because the only other feedback is visual.
 */
function initCopyButtons(): void {
    for (const button of document.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
        const live = document.createElement('span');
        live.className = 'visually-hidden';
        live.setAttribute('role', 'status');
        button.after(live);

        // Captured once: a second click while the first is still showing
        // "Copied" must not teach the button that "Copied" is its label.
        const label = button.textContent ?? 'Copy';
        let timer: ReturnType<typeof setTimeout> | undefined;

        button.addEventListener('click', async () => {
            const value = button.dataset.copy ?? '';
            try {
                await navigator.clipboard.writeText(value);
            } catch {
                // Clipboard access can be denied; the text stays selectable.
                return;
            }

            button.dataset.copied = '';
            button.textContent = 'Copied';
            live.textContent = 'Copied to clipboard';

            clearTimeout(timer);
            timer = setTimeout(() => {
                delete button.dataset.copied;
                button.textContent = label;
                live.textContent = '';
            }, 2000);
        });
    }
}

/**
 * Palette controls: any element carrying `data-palette-control` or
 * `data-mode-control` drives the document, and everything registered with
 * `data-palette-sync` reflects it.
 */
function initPaletteControls(): void {
    const sync = (state: PaletteState) => {
        for (const [kind, value] of [
            ['palette', state.palette],
            ['mode', state.mode],
        ] as const) {
            for (const control of document.querySelectorAll<HTMLElement>(`[data-${kind}-sync]`)) {
                const own = kind === 'palette' ? control.dataset.paletteSync : control.dataset.modeSync;
                control.setAttribute('aria-pressed', String(own === value));
            }
        }
    };

    for (const control of document.querySelectorAll<HTMLElement>('[data-palette-control]')) {
        control.addEventListener('click', () => {
            setPalette(control.dataset.paletteControl ?? '');

            // A palette that ships one mode takes the site with it. That is what
            // picking a palette does in Nexus: the choice sets both, and a
            // dark-only palette left in light mode would render as the brand's
            // light palette under another palette's name.
            const supported = (control.dataset.paletteModes ?? '').split(/\s+/).filter(Boolean);
            const mode = document.documentElement.dataset.mode === 'light' ? 'light' : 'dark';
            if (supported.length > 0 && !supported.includes(mode)) {
                setMode(supported.includes('dark') ? 'dark' : 'light');
            }
        });
    }
    for (const control of document.querySelectorAll<HTMLElement>('[data-mode-control]')) {
        control.addEventListener('click', () => setMode(control.dataset.modeControl === 'light' ? 'light' : 'dark'));
    }

    /** The mode buttons offer only the modes the chosen palette actually has. */
    const syncModes = (palette: string): void => {
        const option = document.querySelector<HTMLElement>(`[data-palette-control='${palette}']`);
        const supported = (option?.dataset.paletteModes ?? 'dark light').split(/\s+/).filter(Boolean);

        for (const button of document.querySelectorAll<HTMLButtonElement>('[data-mode-option]')) {
            button.disabled = !supported.includes(button.dataset.modeOption ?? 'dark');
        }
    };

    document.addEventListener(PALETTE_EVENT, (event) => {
        const state = (event as CustomEvent<PaletteState>).detail;
        sync(state);
        syncModes(state.palette);
    });
    sync(getState());
    syncModes(getState().palette);
}

/**
 * The command that reproduces the visitor's choice in the shell. It is shown
 * next to the picker so the site and the desktop end up on the same palette,
 * which is the point of mirroring the scheme files at all.
 */
function initPaletteCommand(): void {
    const output = document.querySelector<HTMLElement>('[data-command-output]');
    const copy = document.querySelector<HTMLButtonElement>('[data-command-copy]');
    if (!output) return;

    const update = (state: PaletteState) => {
        const option = document.querySelector<HTMLElement>(`[data-palette-control='${state.palette}']`);
        const command = state.mode === 'light' ? option?.dataset.commandLight : option?.dataset.commandDark;
        if (!command) return;
        output.textContent = command;
        if (copy) copy.dataset.copy = command;
    };

    document.addEventListener(PALETTE_EVENT, (event) => update((event as CustomEvent<PaletteState>).detail));
    update(getState());
}

function init(): void {
    initReveals();
    initCopyButtons();
    initPaletteControls();
    initPaletteCommand();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
} else {
    init();
}
