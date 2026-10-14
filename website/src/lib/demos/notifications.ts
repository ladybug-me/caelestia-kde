/**
 * The notification stack.
 *
 * Modelled on the shell's own popup (`shell/modules/notifications`): a card
 * swipes on one axis only, its timeout stops while you are pointing at it, and
 * a swipe either way clears it.
 *
 * What the demo exists for is the part that is hard to get right without
 * springs: the card can be caught mid-dismiss and pulled back, and the stack
 * closes up around it rather than jumping.
 */

import { currentTranslateX, springTo, stopSpring } from '../motion/animate';
import { flip } from '../motion/flip';
import { draggable, type DragHandle } from '../motion/pointer';
import { isDismissed } from '../motion/projection';
import { prefersReducedMotion } from '../motion/prefers';

// Fraction of the card's width that counts as off the edge. The shell's popup
// uses the same shape of threshold (`Config.notifs.clearThreshold`).
const CLOSE_DISTANCE = 0.4;

// A replacement card, so the stack does not run out while someone plays.
const SPARE = {
    app: 'Calendar',
    summary: 'Standup in 15 minutes',
    body: 'Weekly sync · Meeting room 2',
};

export function initNotificationsDemo(root: HTMLElement): () => void {
    const found = root.querySelector<HTMLElement>('[data-notif-stack]');
    const live = root.querySelector<HTMLElement>('[data-notif-live]');
    const template = root.querySelector<HTMLTemplateElement>('[data-notif-template]');
    if (!found) return () => {};
    const stack = found;

    const drags: DragHandle[] = [];
    const timers: Array<ReturnType<typeof setTimeout>> = [];

    const say = (message: string): void => {
        if (live) live.textContent = message;
    };

    function dismiss(card: HTMLElement): void {
        const app = card.dataset.app ?? 'Notification';

        // The stack closes up around the card as it leaves, on a spring, so the
        // cards below travel instead of jumping.
        flip(stack, () => card.remove(), { spring: 'settle' });
        say(`${app} dismissed`);

        if (!template || stack.querySelectorAll('[data-notif]').length >= 3) return;

        timers.push(
            setTimeout(() => {
                const clone = template.content.firstElementChild?.cloneNode(true) as HTMLElement | undefined;
                if (!clone) return;
                clone.dataset.app = SPARE.app;
                clone.querySelector<HTMLElement>('[data-notif-app]')!.textContent = SPARE.app;
                clone.querySelector<HTMLElement>('[data-notif-summary]')!.textContent = SPARE.summary;
                clone.querySelector<HTMLElement>('[data-notif-body]')!.textContent = SPARE.body;
                stack.prepend(clone);
                wire(clone);
            }, 900),
        );
    }

    function wire(card: HTMLElement): void {
        const progress = card.querySelector<HTMLElement>('[data-notif-progress]');
        const close = card.querySelector<HTMLButtonElement>('[data-notif-close]');
        // Where the card was when the pointer took hold of it, so the drag can be
        // measured from the card's position rather than from its rest position.
        let grabOrigin = 0;
        let grabbed = false;

        // Hover pauses the timeout: reading a notification should never race it.
        card.addEventListener('pointerenter', () => {
            if (progress) progress.style.animationPlayState = 'paused';
        });
        card.addEventListener('pointerleave', () => {
            if (progress) progress.style.animationPlayState = 'running';
        });

        close?.addEventListener('click', () => {
            springTo(card, { x: card.offsetWidth + 40, opacity: 0 }, { spring: 'momentum', velocity: 900 });
            timers.push(setTimeout(() => dismiss(card), 160));
        });

        drags.push(
            draggable({
                element: card,
                lock: 'x',
                onDrag: ({ offset }) => {
                    // 1:1 with the pointer, measured from where the card actually
                    // was when it was grabbed — a card caught mid-dismiss
                    // continues from there instead of jumping back to rest.
                    if (!grabbed) {
                        stopSpring(card);
                        grabOrigin = currentTranslateX(card);
                        grabbed = true;
                    }

                    const width = card.offsetWidth || 320;
                    const total = grabOrigin + offset;
                    const travelled = Math.abs(total) / width;
                    // A slight lean as it goes, which is the only embellishment,
                    // and it goes away as the card comes back.
                    card.style.transform = `translateX(${total.toFixed(1)}px) rotate(${(total / 40).toFixed(2)}deg)`;
                    card.style.opacity = String(Math.max(0.35, 1 - travelled * 0.6));
                },
                onRelease: ({ offset, velocity }) => {
                    grabbed = false;
                    const width = card.offsetWidth || 320;
                    const total = grabOrigin + offset;
                    const dismissed = prefersReducedMotion()
                        ? Math.abs(total) >= width * CLOSE_DISTANCE
                        : isDismissed({ offset: total, velocity, size: width, distanceFraction: CLOSE_DISTANCE });

                    if (dismissed) {
                        const direction = Math.sign(total || velocity || 1);
                        springTo(card, { x: direction * (width + 40), opacity: 0 }, { spring: 'momentum', velocity });
                        timers.push(setTimeout(() => dismiss(card), 140));
                        return;
                    }

                    // Not dismissed: the card comes back carrying the velocity it
                    // still had, so the return reads as the same gesture
                    // reversing rather than a new one starting.
                    springTo(card, { x: 0, opacity: 1, rotate: 0 }, { spring: 'momentum', velocity });
                },
                onCancel: () => {
                    grabbed = false;
                    springTo(card, { x: 0, opacity: 1, rotate: 0 }, { spring: 'settle' });
                },
            }),
        );
    }

    for (const card of stack.querySelectorAll<HTMLElement>('[data-notif]')) wire(card);

    return () => {
        timers.forEach(clearTimeout);
        drags.forEach((drag) => drag.destroy());
    };
}
