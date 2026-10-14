/**
 * The bar and its popouts.
 *
 * The rules this demo exists to show:
 *
 *   - A popout comes *from* the element that opened it: its transform origin is
 *     set to that element's centre, so the surface grows out of the thing you
 *     pressed rather than out of its own middle.
 *   - It leaves the way it came. Closing runs the same path in reverse.
 *   - It can be dragged 1:1 from the moment it is open, past the ends of its
 *     travel with resistance rather than a stop.
 *   - A release is a throw: velocity decides whether it opens or closes, and
 *     only a slow release falls back to how far it got.
 *   - Grabbing it while it is animating cancels the animation and continues
 *     from where the surface actually is.
 */

import { currentTranslateY, springTo, stopSpring } from '../motion/animate';
import { draggable, type DragHandle } from '../motion/pointer';
import { clampWithResistance } from '../motion/projection';

// A release faster than this is a throw and its direction is the whole answer.
// Slower than this, distance decides. The same constant the notifications and
// the pager use.
export const THROW_VELOCITY = 400;

interface Surface {
    trigger: HTMLElement;
    panel: HTMLElement;
    drag: DragHandle;
}

/** Places the transform origin over the element that opened the popout. */
function anchorTo(panel: HTMLElement, trigger: HTMLElement): void {
    const panelBox = panel.getBoundingClientRect();
    const triggerBox = trigger.getBoundingClientRect();
    if (panelBox.width === 0 || panelBox.height === 0) return;

    const x = ((triggerBox.left + triggerBox.width / 2 - panelBox.left) / panelBox.width) * 100;
    const y = ((triggerBox.top + triggerBox.height / 2 - panelBox.top) / panelBox.height) * 100;
    panel.style.transformOrigin = `${x.toFixed(1)}% ${y.toFixed(1)}%`;
}

export function initBarDemo(root: HTMLElement): () => void {
    const surfaces: Surface[] = [];
    const live = root.querySelector<HTMLElement>('[data-bar-live]');
    let open: Surface | null = null;

    const say = (message: string): void => {
        if (live) live.textContent = message;
    };

    function close(surface: Surface, velocity = 0): void {
        const { panel, trigger } = surface;
        const travel = panel.offsetHeight;

        trigger.setAttribute('aria-expanded', 'false');
        panel.classList.remove('is-open');
        panel.dataset.state = 'closing';

        springTo(
            panel,
            { y: travel, opacity: 0, scale: 0.98 },
            {
                spring: velocity === 0 ? 'drawer' : 'momentum',
                velocity: velocity === 0 ? undefined : { y: velocity },
                onSettle: () => {
                    if (panel.dataset.state !== 'closing') return;
                    panel.hidden = true;
                    panel.style.transform = '';
                    panel.style.opacity = '';
                    delete panel.dataset.state;
                    say(`${trigger.textContent?.trim() ?? 'Popout'} closed`);
                },
            },
        );
        if (open === surface) open = null;
    }

    function show(surface: Surface): void {
        if (open === surface) return;
        if (open) close(open);
        open = surface;

        const { panel, trigger } = surface;

        // The panel has to be laid out before the origin can be measured from
        // it: while it is hidden, every box is zero.
        panel.hidden = false;
        anchorTo(panel, trigger);

        panel.dataset.state = 'open';
        trigger.setAttribute('aria-expanded', 'true');

        springTo(panel, { y: 0, opacity: 1, scale: 1 }, { spring: 'drawer' });
        panel.classList.add('is-open');
        say(`${trigger.textContent?.trim() ?? 'Popout'} opened`);
    }

    for (const trigger of root.querySelectorAll<HTMLElement>('[data-popout]')) {
        const panel = root.querySelector<HTMLElement>(`[data-popout-panel='${trigger.dataset.popout}']`);
        if (!panel) continue;

        panel.hidden = true;

        let grabOrigin = 0;

        const surface: Surface = {
            trigger,
            panel,
            drag: draggable({
                element: panel,
                lock: 'y',
                onDrag: ({ offset }) => {
                    if (panel.dataset.state !== 'dragging') {
                        // Taking hold of a moving surface stops the animation and
                        // remembers the position that is actually on screen: never
                        // the value the animation was heading for.
                        stopSpring(panel);
                        grabOrigin = currentTranslateY(panel);
                        panel.dataset.state = 'dragging';
                    }

                    const travel = panel.offsetHeight;
                    const came = grabOrigin + offset;
                    panel.style.opacity = came > 0 ? '0.92' : '1';
                    panel.style.transform = `translateY(${clampWithResistance(came, 0, travel, travel).toFixed(1)}px)`;
                },
                onRelease: ({ offset, velocity }) => {
                    const travel = panel.offsetHeight;
                    const came = grabOrigin + offset;
                    panel.dataset.state = 'open';

                    // A throw decides by its direction; a slow release by how far
                    // it got.
                    const closing = Math.abs(velocity) >= THROW_VELOCITY ? velocity > 0 : came > travel / 2;
                    if (closing) {
                        close(surface, Math.max(0, velocity));
                        return;
                    }

                    springTo(
                        panel,
                        { y: 0, opacity: 1 },
                        {
                            spring: Math.abs(velocity) > THROW_VELOCITY ? 'momentum' : 'settle',
                            velocity: velocity === 0 ? undefined : { y: velocity },
                        },
                    );
                },
                onCancel: () => {
                    panel.dataset.state = 'open';
                    springTo(panel, { y: 0, opacity: 1 }, { spring: 'settle' });
                },
            }),
        };

        surfaces.push(surface);

        trigger.addEventListener('click', () => {
            panel.dataset.state = 'open';
            if (open === surface) close(surface);
            else show(surface);
        });

        panel.addEventListener('keydown', (event) => {
            if (event.key !== 'Escape') return;
            event.stopPropagation();
            close(surface);
            trigger.focus();
        });
    }

    // A press anywhere else shuts the open popout, the way clicking off a
    // popout on the desktop does.
    const outside = (event: PointerEvent): void => {
        if (!open) return;
        const target = event.target as Node;
        if (open.panel.contains(target) || open.trigger.contains(target)) return;
        close(open);
    };
    document.addEventListener('pointerdown', outside, true);

    return () => {
        document.removeEventListener('pointerdown', outside, true);
        surfaces.forEach((surface) => surface.drag.destroy());
    };
}
