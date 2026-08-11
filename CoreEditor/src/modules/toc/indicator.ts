import { EditorView, ViewPlugin, ViewUpdate } from '@codemirror/view';
import { EditorState } from '@codemirror/state';
import { getTableOfContents, gotoHeader, HeadingInfo } from './index';

/**
 * Claude Code-style chapter indicator: a fixed column of dashes at the
 * top-left of the document, one per heading (longer = higher level).
 * Hovering swaps the dashes for the full table of contents; clicking an
 * entry jumps to that section. Can also be opened via keyboard (bridge
 * togglePopover): arrows navigate, enter jumps, escape closes.
 */
class TocIndicator {
  private readonly container: HTMLElement;
  private readonly dashes: HTMLElement;
  private readonly panel: HTMLElement;
  private readonly view: EditorView;
  private rows: { element: HTMLElement; info: HeadingInfo }[] = [];
  private pending = false;
  private destroyed = false;
  private keyboardActive = false;
  private activeIndex = 0;

  constructor(view: EditorView) {
    this.view = view;
    this.container = document.createElement('div');
    this.container.className = 'cm-md-tocIndicator';

    this.dashes = document.createElement('div');
    this.dashes.className = 'cm-md-tocDashes';

    this.panel = document.createElement('div');
    this.panel.className = 'cm-md-tocPanel';

    this.container.appendChild(this.dashes);
    this.container.appendChild(this.panel);
    this.container.onmouseleave = () => this.container.classList.remove('cm-md-tocSuppressed');
    view.dom.appendChild(this.container);
    this.scheduleRebuild();

    activeToggle = () => this.toggleKeyboard();
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.selectionSet) {
      this.scheduleRebuild();
    }
  }

  destroy() {
    this.destroyed = true;
    this.closeKeyboard();
    this.container.remove();
    activeToggle = null;
  }

  toggleKeyboard() {
    if (this.keyboardActive) {
      this.closeKeyboard();
    } else {
      this.openKeyboard();
    }
  }

  private openKeyboard() {
    if (this.rows.length === 0) {
      return;
    }

    this.keyboardActive = true;
    this.container.classList.remove('cm-md-tocSuppressed');
    this.container.classList.add('cm-md-tocKeyboardOpen');

    const selected = this.rows.findIndex(row => row.info.selected);
    this.setActiveIndex(selected >= 0 ? selected : 0);

    // Capture phase so the editor never sees navigation keys while open
    document.addEventListener('keydown', this, true);
    document.addEventListener('mousedown', this, true);
  }

  private closeKeyboard() {
    this.keyboardActive = false;
    this.container.classList.remove('cm-md-tocKeyboardOpen');
    document.removeEventListener('keydown', this, true);
    document.removeEventListener('mousedown', this, true);
  }

  private setActiveIndex(index: number) {
    this.activeIndex = Math.min(Math.max(index, 0), this.rows.length - 1);
    this.rows.forEach((row, rowIndex) => {
      row.element.classList.toggle('cm-md-tocRowKeyActive', rowIndex === this.activeIndex);
    });

    this.rows[this.activeIndex]?.element.scrollIntoView({ block: 'nearest' });
  }

  // EventListenerObject: passing `this` to addEventListener avoids bind(),
  // which this tsconfig types as `any`
  handleEvent(event: Event) {
    if (event instanceof KeyboardEvent) {
      this.handleKeydown(event);
    } else if (event instanceof MouseEvent) {
      this.handleOutsideMousedown(event);
    }
  }

  private handleKeydown(event: KeyboardEvent) {
    const step = (delta: number) => {
      const count = this.rows.length;
      this.setActiveIndex((this.activeIndex + delta + count) % count);
    };

    switch (event.key) {
      case 'ArrowDown': step(1); break;
      case 'ArrowUp': step(-1); break;
      case 'Enter':
        gotoHeader(this.rows[this.activeIndex].info);
        this.closeKeyboard();
        break;
      case 'Escape': this.closeKeyboard(); break;
      default: return;
    }

    event.preventDefault();
    event.stopPropagation();
  }

  private handleOutsideMousedown(event: MouseEvent) {
    if (!this.container.contains(event.target as Node)) {
      this.closeKeyboard();
    }
  }

  // getTableOfContents forces a full syntax parse; doing that inside an
  // update cycle desyncs the highlighter's decorations from the view and
  // leaves ghost characters in the DOM. Always rebuild after the update.
  private scheduleRebuild() {
    if (this.pending) {
      return;
    }

    this.pending = true;
    setTimeout(() => {
      this.pending = false;
      if (!this.destroyed) {
        this.rebuild(this.view.state);
      }
    }, 0);
  }

  private rebuild(state: EditorState) {
    const toc = getTableOfContents(state);
    this.container.style.display = toc.length > 0 ? '' : 'none';
    this.dashes.replaceChildren();
    this.panel.replaceChildren();
    this.rows = [];

    for (const info of toc) {
      const dash = document.createElement('span');
      dash.className = `cm-md-tocDash${info.selected ? ' cm-md-tocDashActive' : ''}`;
      dash.style.width = `${Math.max(5, 14 - (info.level - 1) * 2.5)}px`;
      this.dashes.appendChild(dash);

      const row = document.createElement('div');
      row.className = `cm-md-tocRow${info.selected ? ' cm-md-tocRowActive' : ''}`;
      // Inline style overrides the .cm-md-tocRow shorthand: keep its 12px base
      row.style.paddingLeft = `${12 + (info.level - 1) * 12}px`;
      row.textContent = info.title;

      row.onmousedown = event => event.preventDefault();
      row.onclick = () => {
        gotoHeader(info);
        this.container.classList.add('cm-md-tocSuppressed');
        this.closeKeyboard();
      };

      this.panel.appendChild(row);
      this.rows.push({ element: row, info });
    }

    if (this.keyboardActive) {
      if (this.rows.length === 0) {
        this.closeKeyboard();
      } else {
        this.setActiveIndex(this.activeIndex);
      }
    }
  }
}

let activeToggle: (() => void) | null = null;

export function toggleTocPopover() {
  activeToggle?.();
}

export const tocIndicatorExtension = ViewPlugin.fromClass(TocIndicator);
