import { EditorView, ViewPlugin, ViewUpdate } from '@codemirror/view';
import { EditorState } from '@codemirror/state';
import { getTableOfContents, gotoHeader } from './index';

/**
 * Claude Code-style chapter indicator: a fixed column of dashes at the
 * top-left of the document, one per heading (longer = higher level).
 * Hovering swaps the dashes for the full table of contents; clicking an
 * entry jumps to that section.
 */
class TocIndicator {
  private readonly container: HTMLElement;
  private readonly dashes: HTMLElement;
  private readonly panel: HTMLElement;
  private readonly view: EditorView;
  private pending = false;
  private destroyed = false;

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
    view.dom.appendChild(this.container);
    this.scheduleRebuild();
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.selectionSet) {
      this.scheduleRebuild();
    }
  }

  destroy() {
    this.destroyed = true;
    this.container.remove();
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

    for (const info of toc) {
      const dash = document.createElement('span');
      dash.className = `cm-md-tocDash${info.selected ? ' cm-md-tocDashActive' : ''}`;
      dash.style.width = `${Math.max(5, 14 - (info.level - 1) * 2.5)}px`;
      this.dashes.appendChild(dash);

      const row = document.createElement('div');
      row.className = `cm-md-tocRow${info.selected ? ' cm-md-tocRowActive' : ''}`;
      row.style.paddingLeft = `${(info.level - 1) * 12}px`;
      row.textContent = info.title;

      row.onmousedown = event => event.preventDefault();
      row.onclick = () => gotoHeader(info);
      this.panel.appendChild(row);
    }
  }
}

export const tocIndicatorExtension = ViewPlugin.fromClass(TocIndicator);
