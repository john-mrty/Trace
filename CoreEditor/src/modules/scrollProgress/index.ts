const fadeOutDelay = 800;
let fadeOutTimer: ReturnType<typeof setTimeout> | undefined = undefined;

/**
 * A 2px reading-position bar along the right edge, shown while scrolling.
 * Replaces the native scrollbar, which is hidden in index.css.
 * Call after each editor (re)creation; listeners die with the old scrollDOM.
 */
export function setUpScrollProgress() {
  const scroller = window.editor.scrollDOM;
  const bar = ensureBar();

  const update = () => {
    const maxOffset = scroller.scrollHeight - scroller.clientHeight;
    if (maxOffset <= 0) {
      bar.classList.remove('visible');
      return;
    }

    const trackHeight = scroller.clientHeight;
    const barHeight = Math.max(24, trackHeight * (trackHeight / scroller.scrollHeight));
    const fraction = scroller.scrollTop / maxOffset;
    bar.style.height = `${barHeight}px`;
    bar.style.top = `${scroller.getBoundingClientRect().top + fraction * (trackHeight - barHeight)}px`;

    bar.classList.add('visible');
    clearTimeout(fadeOutTimer);
    fadeOutTimer = setTimeout(() => bar.classList.remove('visible'), fadeOutDelay);
  };

  scroller.addEventListener('scroll', update, { passive: true });
}

function ensureBar() {
  const existing = document.getElementById('scroll-progress');
  if (existing !== null) {
    return existing;
  }

  const bar = document.createElement('div');
  bar.id = 'scroll-progress';
  document.body.appendChild(bar);
  return bar;
}
