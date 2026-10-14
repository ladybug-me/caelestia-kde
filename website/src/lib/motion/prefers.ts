/**
 * Visitor preferences, read once and observed thereafter.
 *
 * Three independent signals, because they are three different problems:
 * motion, transparency and contrast. A visitor who needs one does not
 * necessarily need the others.
 */

const queries = {
    reducedMotion: '(prefers-reduced-motion: reduce)',
    reducedTransparency: '(prefers-reduced-transparency: reduce)',
    moreContrast: '(prefers-contrast: more)',
} as const;

export type Preference = keyof typeof queries;

export function prefers(preference: Preference): boolean {
    return typeof matchMedia === 'function' && matchMedia(queries[preference]).matches;
}

export function prefersReducedMotion(): boolean {
    return prefers('reducedMotion');
}

/**
 * Calls `listener` whenever any of the preferences changes, which is what a
 * demo needs: a visitor can turn reduce-motion on mid-session and the springs
 * have to stop, not wait for a reload.
 */
export function watchPreferences(listener: () => void): () => void {
    if (typeof matchMedia !== 'function') return () => {};

    const lists = Object.values(queries).map((query) => matchMedia(query));
    lists.forEach((list) => list.addEventListener('change', listener));
    return () => lists.forEach((list) => list.removeEventListener('change', listener));
}
