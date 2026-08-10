import { Decoration, DecorationSet, EditorView, WidgetType } from '@codemirror/view';
import { EditorState, Range, RangeSet, StateField } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { createDecoPlugin, lineDecoRanges } from '../helper';
import { frontMatterRange } from '../../modules/frontMatter';

const hiddenDeco = Decoration.replace({});

class BulletWidget extends WidgetType {
  toDOM() {
    const span = document.createElement('span');
    // Reuse the list mark class so the accent color applies
    span.className = 'cm-md-listMark';
    span.textContent = '•';
    return span;
  }

  override eq() {
    return true;
  }
}

const bulletDeco = Decoration.replace({ widget: new BulletWidget() });

class RuleWidget extends WidgetType {
  toDOM() {
    const span = document.createElement('span');
    span.className = 'cm-md-ruleFill';
    return span;
  }

  override eq() {
    return true;
  }
}

const ruleDeco = Decoration.replace({ widget: new RuleWidget() });

class TaskCheckboxWidget extends WidgetType {
  constructor(private readonly checked: boolean) {
    super();
  }

  override eq(other: TaskCheckboxWidget) {
    return other.checked === this.checked;
  }

  toDOM() {
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.className = 'cm-md-taskCheckbox';
    input.checked = this.checked;

    input.onmousedown = event => {
      event.preventDefault();
      event.stopPropagation();
    };

    input.onclick = event => {
      event.preventDefault();
      event.stopPropagation();

      const editor = window.editor;
      const from = editor.posAtDOM(input);
      const marker = editor.state.sliceDoc(from, from + 3);
      editor.dispatch({
        changes: { from, to: from + 3, insert: marker === '[ ]' ? '[x]' : '[ ]' },
        userEvent: '@none',
      });
    };

    return input;
  }
}

function showLightbox(source: string) {
  const overlay = document.createElement('div');
  overlay.className = 'cm-md-lightbox';

  const image = document.createElement('img');
  image.src = source;
  overlay.appendChild(image);

  const dismiss = () => {
    overlay.remove();
    document.removeEventListener('keydown', onKeyDown, true);
  };

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      dismiss();
    }
  };

  overlay.onclick = dismiss;
  document.addEventListener('keydown', onKeyDown, true);

  // Theme rules are scoped to the editor element; on body the overlay is unstyled
  window.editor.dom.appendChild(overlay);
}

class InlineImageWidget extends WidgetType {
  constructor(private readonly source: string, private readonly altText: string) {
    super();
  }

  override eq(other: InlineImageWidget) {
    return other.source === this.source && other.altText === this.altText;
  }

  override ignoreEvent() {
    return false;
  }

  toDOM() {
    const span = document.createElement('span');
    const img = document.createElement('img');
    img.className = 'cm-md-inlineImage';
    img.alt = this.altText;

    // Absolute URLs load directly; file paths ride in a query param because
    // URL normalization eats "../" segments in the path slot, and the host
    // slot rejects spaces. The host+path shape also satisfies WebKit's
    // scheme-task allowlist pattern ("image-loader://*/*").
    const hasScheme = /^[a-z][a-z0-9+.-]*:/i.test(this.source);
    img.src = hasScheme ? this.source : `image-loader://asset/img?src=${encodeURIComponent(this.source)}`;

    img.onmousedown = event => {
      event.preventDefault();
      event.stopPropagation();
    };

    img.onclick = event => {
      event.preventDefault();
      event.stopPropagation();
      showLightbox(img.src);
    };

    img.onload = () => window.editor.requestMeasure();
    img.onerror = () => {
      img.remove();
      span.className = 'cm-md-brokenImage';
      span.textContent = this.altText.length > 0 ? this.altText : this.source;
    };

    span.appendChild(img);
    return span;
  }
}

const copyIcon = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
const checkIcon = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

async function copyToClipboard(text: string) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    textarea.remove();
  }
}

class CodeChromeWidget extends WidgetType {
  constructor(private readonly language: string, private readonly code: string) {
    super();
  }

  override eq(other: CodeChromeWidget) {
    return other.language === this.language && other.code === this.code;
  }

  override ignoreEvent() {
    return false;
  }

  toDOM() {
    const chrome = document.createElement('span');
    chrome.className = 'cm-md-codeChrome';

    if (this.language.length > 0) {
      const lang = document.createElement('span');
      lang.className = 'cm-md-codeLang';
      lang.textContent = this.language;
      chrome.appendChild(lang);
    }

    const copy = document.createElement('span');
    copy.className = 'cm-md-codeCopy';
    copy.innerHTML = copyIcon;

    copy.onmousedown = event => {
      event.preventDefault();
      event.stopPropagation();
    };

    copy.onclick = event => {
      event.preventDefault();
      event.stopPropagation();
      void copyToClipboard(this.code);
      copy.innerHTML = checkIcon;
      setTimeout(() => { copy.innerHTML = copyIcon; }, 1200);
    };

    chrome.appendChild(copy);
    return chrome;
  }
}

// Extras are display-only (line styles, tooltips, badges); they must never
// feed atomicRanges or the caret would skip entire lines
function collectConcealed(view: EditorView) {
  const state = view.state;

  const ranges: Range<Decoration>[] = [];
  const extras: Range<Decoration>[] = [];
  const conceal = (from: number, to: number) => {
    ranges.push(hiddenDeco.range(from, to));
  };

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from, to,
      enter: node => {
        const parent = node.node.parent?.type.name ?? '';
        switch (node.name) {
          case 'HeaderMark':
            // ATX only (Setext underlines stay visible); swallow the "# " space
            if (parent.startsWith('ATXHeading')) {
              const next = state.sliceDoc(node.to, node.to + 1);
              conceal(node.from, next === ' ' ? node.to + 1 : node.to);
            }
            break;
          case 'EmphasisMark':
          case 'StrikethroughMark':
            conceal(node.from, node.to);
            break;
          case 'CodeMark':
            if (parent === 'InlineCode' || parent === 'FencedCode') {
              conceal(node.from, node.to);
            }
            break;
          case 'HorizontalRule':
            // "---" reads as a low-contrast full-width rule
            ranges.push(ruleDeco.range(node.from, node.to));
            break;
          case 'ListMark':
            // Task items render as a checkbox only — swallow the list mark and
            // its trailing space so "- [ ] Item" reads as "☐ Item"
            if (/^ \[[ xX]\]/.test(state.sliceDoc(node.to, node.to + 4))) {
              conceal(node.from, node.to + 1);
            } else if (state.sliceDoc(node.from, node.to) === '*') {
              // "* Item" reads as a round bullet; "-" and "+" keep their literal glyphs
              ranges.push(bulletDeco.range(node.from, node.to));
            }
            break;
          case 'TaskMarker': {
            const checked = state.sliceDoc(node.from, node.to) !== '[ ]';
            ranges.push(Decoration.replace({
              widget: new TaskCheckboxWidget(checked),
            }).range(node.from, node.to));

            if (checked) {
              extras.push(Decoration.line({ class: 'cm-md-taskDone' }).range(state.doc.lineAt(node.from).from));
            }
            break;
          }
          case 'LinkMark':
          case 'URL':
            // Link only: images and autolinks keep their syntax
            if (parent === 'Link') {
              conceal(node.from, node.to);
            }
            break;
          case 'Link': {
            // Destination is invisible in concealed mode; surface it on hover
            const urlNode = node.node.getChildren('URL').pop();
            if (urlNode !== undefined) {
              const url = state.sliceDoc(urlNode.from, urlNode.to).replace(/^<|>$/g, '');
              extras.push(Decoration.mark({ attributes: { title: url } }).range(node.from, node.to));
            }
            break;
          }
          case 'QuoteMark': {
            // "> " vanishes; the quote bar comes from the Blockquote line style
            const next = state.sliceDoc(node.to, node.to + 1);
            conceal(node.from, next === ' ' ? node.to + 1 : node.to);
            break;
          }
          case 'Blockquote':
            extras.push(...lineDecoRanges(node.from, node.to, 'cm-md-quoteLine'));
            break;
          case 'FencedCode': {
            // Fence lines conceal to short empty lines, acting as the panel's padding
            const firstLine = state.doc.lineAt(node.from);
            const lastLine = state.doc.lineAt(node.to);
            for (let lineNumber = firstLine.number; lineNumber <= lastLine.number; ++lineNumber) {
              const line = state.doc.line(lineNumber);
              const edges = `${lineNumber === firstLine.number ? ' cm-md-codePanelFirst' : ''}${lineNumber === lastLine.number ? ' cm-md-codePanelLast' : ''}`;
              extras.push(Decoration.line({ class: `cm-md-codePanel${edges}` }).range(line.from));
            }

            const infoNode = node.node.getChild('CodeInfo');
            const language = infoNode === null ? '' : state.sliceDoc(infoNode.from, infoNode.to);
            const code = lastLine.number > firstLine.number + 1
              ? state.sliceDoc(state.doc.line(firstLine.number + 1).from, state.doc.line(lastLine.number - 1).to)
              : '';
            extras.push(Decoration.widget({
              widget: new CodeChromeWidget(language, code),
              side: 1,
            }).range(firstLine.to));
            break;
          }
          case 'CodeInfo':
            conceal(node.from, node.to);
            break;
          case 'Image': {
            // Last URL child: "name@2x.png" in the alt text parses as an email
            // autolink, adding a URL node before the real destination
            const urlNode = node.node.getChildren('URL').pop() ?? null;
            const sameLine = state.doc.lineAt(node.from).number === state.doc.lineAt(node.to).number;
            if (urlNode !== null && sameLine) {
              const source = state.sliceDoc(urlNode.from, urlNode.to).replace(/^<|>$/g, '');
              const altText = state.sliceDoc(node.from, node.to).match(/^!\[((?:\\.|[^\]\\])*)\]/)?.[1] ?? '';
              ranges.push(Decoration.replace({
                widget: new InlineImageWidget(source, altText),
              }).range(node.from, node.to));
              return false;
            }
            break;
          }
          default:
            break;
        }
      },
    });
  }

  return { conceal: ranges, extras };
}

// Atomic ranges: only true concealments, so the caret skips hidden marks
function concealedRanges(view: EditorView) {
  return Decoration.set(collectConcealed(view).conceal, true);
}

function concealedDecorations(view: EditorView) {
  const { conceal, extras } = collectConcealed(view);
  return Decoration.set([...conceal, ...extras], true);
}

/**
 * Live-preview concealment: replaces markdown syntax marks with nothing,
 * everywhere — including the cursor line. View-layer only — the
 * document, undo, search, and copy are untouched.
 *
 * atomicRanges makes the caret skip over concealed marks instead of
 * landing invisibly inside them.
 */
class TablePreviewWidget extends WidgetType {
  constructor(private readonly markdown: string) {
    super();
  }

  override eq(other: TablePreviewWidget) {
    return other.markdown === this.markdown;
  }

  override ignoreEvent() {
    return false;
  }

  override get estimatedHeight() {
    return this.markdown.split('\n').length * 30;
  }

  toDOM() {
    const table = document.createElement('table');
    table.className = 'cm-md-tablePreview';

    const parseCells = (line: string) => {
      const inner = line.replace(/^\s*\|/, '').replace(/\|\s*$/, '');
      return inner.split(/(?<!\\)\|/).map(cell => cell.trim().replace(/\\\|/g, '|'));
    };

    this.markdown.split('\n').forEach((line, index) => {
      // The |---|:---:| separator row defines alignment, it isn't content
      if (index === 1 && /^[\s|:-]+$/.test(line)) {
        return;
      }

      const row = document.createElement('tr');
      for (const cell of parseCells(line)) {
        const element = document.createElement(index === 0 ? 'th' : 'td');
        element.textContent = cell;
        row.appendChild(element);
      }

      table.appendChild(row);
    });

    return table;
  }
}

function tableDecorations(state: EditorState): DecorationSet {
  const ranges: Range<Decoration>[] = [];

  syntaxTree(state).iterate({
    enter: node => {
      if (node.name !== 'Table') {
        return;
      }

      ranges.push(Decoration.replace({
        widget: new TablePreviewWidget(state.sliceDoc(node.from, node.to)),
        block: true,
      }).range(node.from, node.to));

      return false;
    },
  });

  return Decoration.set(ranges, true);
}

// Block widgets (a rendered table replaces multiple lines) must come from a
// StateField, view plugins are not allowed to affect vertical layout
const tablePreviewField = StateField.define<DecorationSet>({
  create: state => tableDecorations(state),
  update: (value, tr) => {
    if (tr.docChanged || syntaxTree(tr.state) !== syntaxTree(tr.startState)) {
      return tableDecorations(tr.state);
    }

    return value;
  },
  provide: field => EditorView.decorations.from(field),
});

class FrontMatterChipWidget extends WidgetType {
  constructor(private readonly yaml: string) {
    super();
  }

  override eq(other: FrontMatterChipWidget) {
    return other.yaml === this.yaml;
  }

  override ignoreEvent() {
    return false;
  }

  toDOM() {
    const container = document.createElement('div');
    container.className = 'cm-md-frontMatter';

    const entries = this.yaml.split('\n')
      .map(line => /^(\S[^:]*):\s*(.*)$/.exec(line))
      .filter((match): match is RegExpExecArray => match !== null)
      .map(match => [match[1].trim(), match[2].trim()] as const);

    const chip = document.createElement('span');
    chip.className = 'cm-md-frontMatterChip';
    chip.textContent = `Properties · ${entries.length}`;
    container.appendChild(chip);

    const table = document.createElement('div');
    table.className = 'cm-md-frontMatterTable';
    table.style.display = 'none';

    for (const [key, value] of entries) {
      const row = document.createElement('div');
      const keySpan = document.createElement('span');
      keySpan.className = 'cm-md-frontMatterKey';
      keySpan.textContent = key;

      const valueSpan = document.createElement('span');
      valueSpan.textContent = value;

      row.appendChild(keySpan);
      row.appendChild(valueSpan);
      table.appendChild(row);
    }

    container.appendChild(table);

    chip.onmousedown = event => {
      event.preventDefault();
      event.stopPropagation();
    };

    chip.onclick = event => {
      event.preventDefault();
      event.stopPropagation();
      const expanded = table.style.display !== 'none';
      table.style.display = expanded ? 'none' : 'block';
      chip.classList.toggle('cm-md-frontMatterChipOpen', !expanded);
      window.editor.requestMeasure();
    };

    return container;
  }
}

function frontMatterDecorations(state: EditorState): DecorationSet {
  // Pass the text explicitly: this runs during editor creation,
  // before window.editor (which the argless overload reads) exists
  const range = frontMatterRange(state.doc.toString());
  if (range === undefined) {
    return Decoration.set([]);
  }

  // Strip the "---" fences; the widget parses only the inner YAML lines
  const yaml = state.sliceDoc(range.from, range.to).replace(/^---[ \t]*\r?\n?|\r?\n?---[ \t]*$/g, '');
  return Decoration.set([
    Decoration.replace({
      widget: new FrontMatterChipWidget(yaml),
      block: true,
    }).range(range.from, range.to),
  ]);
}

const frontMatterField = StateField.define<DecorationSet>({
  create: state => frontMatterDecorations(state),
  update: (value, tr) => {
    if (tr.docChanged || syntaxTree(tr.state) !== syntaxTree(tr.startState)) {
      return frontMatterDecorations(tr.state);
    }

    return value;
  },
  provide: field => EditorView.decorations.from(field),
});

export const concealExtension = [
  createDecoPlugin(() => concealedDecorations(window.editor)),
  EditorView.atomicRanges.of(view => {
    try {
      return concealedRanges(view);
    } catch {
      return RangeSet.empty;
    }
  }),
  tablePreviewField,
  EditorView.atomicRanges.of(view => view.state.field(tablePreviewField)),
  frontMatterField,
  EditorView.atomicRanges.of(view => view.state.field(frontMatterField)),
];
