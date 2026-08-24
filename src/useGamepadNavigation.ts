import { useEffect, useRef } from 'react';

const selector = 'button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex="0"]';

type FocusDirection = 'up' | 'down' | 'left' | 'right';

function visibleControls() {
  const scope = document.querySelector('.confirm-modal') ?? document;
  return [...scope.querySelectorAll<HTMLElement>(selector)].filter((element) => {
    const style = window.getComputedStyle(element);
    return element.offsetParent !== null && style.visibility !== 'hidden';
  });
}

function focusElement(element: HTMLElement | null | undefined) {
  if (!element) return;
  element.focus({ preventScroll: true });
  element.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
}

export function useGamepadNavigation(enabled: boolean) {
  const previous = useRef<boolean[]>([]);
  const axisLatch = useRef({ vertical: 0, horizontal: 0 });

  useEffect(() => {
    if (!enabled) return;

    const moveFocus = (direction: FocusDirection) => {
      const controls = visibleControls();
      if (!controls.length) return;

      const active = document.activeElement instanceof HTMLElement && controls.includes(document.activeElement)
        ? document.activeElement
        : document.querySelector<HTMLElement>('.nav-item.active') ?? controls[0];
      const origin = active.getBoundingClientRect();
      const originX = origin.left + origin.width / 2;
      const originY = origin.top + origin.height / 2;

      let best: HTMLElement | undefined;
      let bestScore = Number.POSITIVE_INFINITY;

      for (const candidate of controls) {
        if (candidate === active) continue;
        const rect = candidate.getBoundingClientRect();
        const dx = rect.left + rect.width / 2 - originX;
        const dy = rect.top + rect.height / 2 - originY;
        const horizontal = direction === 'left' || direction === 'right';
        const primary = horizontal ? Math.abs(dx) : Math.abs(dy);
        const cross = horizontal ? Math.abs(dy) : Math.abs(dx);
        const isAhead = direction === 'left' ? dx < -2
          : direction === 'right' ? dx > 2
            : direction === 'up' ? dy < -2
              : dy > 2;
        if (!isAhead) continue;

        const score = primary + cross * 1.8 + (cross / Math.max(primary, 1)) * 70;
        if (score < bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      if (!best && direction === 'right' && active.closest('.sidebar')) {
        best = controls.find((control) => !control.closest('.sidebar'));
      }
      if (!best && direction === 'left' && !active.closest('.sidebar')) {
        best = document.querySelector<HTMLElement>('.nav-item.active') ?? undefined;
      }
      focusElement(best);
    };

    const changeSection = (direction: 1 | -1) => {
      const sections = [...document.querySelectorAll<HTMLButtonElement>('.nav-item')];
      const current = Math.max(0, sections.findIndex((element) => element.classList.contains('active')));
      sections[(current + direction + sections.length) % sections.length]?.click();
      window.setTimeout(() => focusElement(document.querySelector<HTMLButtonElement>('.nav-item.active')), 30);
    };

    const timer = window.setInterval(() => {
      const pad = navigator.getGamepads?.()[0];
      if (!pad) return;
      const pressed = pad.buttons.map((button) => button.pressed);
      const edge = (index: number) => pressed[index] && !previous.current[index];
      const vertical = Math.abs(pad.axes[1] || 0) > .65 ? Math.sign(pad.axes[1]) : 0;
      const horizontal = Math.abs(pad.axes[0] || 0) > .65 ? Math.sign(pad.axes[0]) : 0;

      if (edge(12) || (vertical < 0 && axisLatch.current.vertical === 0)) moveFocus('up');
      if (edge(13) || (vertical > 0 && axisLatch.current.vertical === 0)) moveFocus('down');
      if (edge(14) || (horizontal < 0 && axisLatch.current.horizontal === 0)) moveFocus('left');
      if (edge(15) || (horizontal > 0 && axisLatch.current.horizontal === 0)) moveFocus('right');
      if (edge(0)) (document.activeElement as HTMLElement)?.click();
      if (edge(1)) window.dispatchEvent(new CustomEvent('azeroth-gamepad-back'));
      if (edge(9)) document.querySelector<HTMLButtonElement>('[data-gamepad-launch-wow="true"]')?.click();
      if (edge(4)) changeSection(-1);
      if (edge(5)) changeSection(1);
      if (edge(2)) {
        const active = document.activeElement;
        const acceptsText = active instanceof HTMLTextAreaElement || (
          active instanceof HTMLInputElement && !['button', 'checkbox', 'radio', 'range', 'submit'].includes(active.type)
        );
        if (acceptsText) {
          active.focus({ preventScroll: true });
          void window.azerothDesktop?.openKeyboard();
        } else {
          document.querySelector<HTMLButtonElement>('.icon-button')?.click();
        }
      }
      previous.current = pressed;
      axisLatch.current = { vertical, horizontal };
    }, 70);

    const initial = window.setTimeout(
      () => focusElement(document.querySelector<HTMLButtonElement>('.nav-item.active')),
      150,
    );
    return () => {
      window.clearInterval(timer);
      window.clearTimeout(initial);
    };
  }, [enabled]);
}
