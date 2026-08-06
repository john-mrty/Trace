import { Decoration, DecorationSet, EditorView, WidgetType } from '@codemirror/view';
import { EditorState, Range, RangeSet, StateField } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { createDecoPlugin } from '../helper';

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

    // Absolute URLs load directly; bare paths resolve
    // against the document folder via the image-loader scheme
    const hasScheme = /^[a-z][a-z0-9+.-]*:/i.test(this.source);
    img.src = hasScheme ? this.source : `image-loader://${encodeURI(this.source)}`;

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

function concealedRanges(view: EditorView) {
  const state = view.state;

  const ranges: Range<Decoration>[] = [];
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
            if (parent === 'InlineCode') {
              conceal(node.from, node.to);
            }
            break;
          case 'HorizontalRule':
            // "---" reads as a low-contrast full-width rule
            ranges.push(ruleDeco.range(node.from, node.to));
            break;
          case 'ListMark':
            // "* Item" reads as a round bullet; "-" and "+" keep their literal glyphs
            if (state.sliceDoc(node.from, node.to) === '*') {
              ranges.push(bulletDeco.range(node.from, node.to));
            }
            break;
          case 'LinkMark':
          case 'URL':
            // Link only: images and autolinks keep their syntax
            if (parent === 'Link') {
              conceal(node.from, node.to);
            }
            break;
          case 'Image': {
            const urlNode = node.node.getChild('URL');
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

  return Decoration.set(ranges, true);
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

export const concealExtension = [
  createDecoPlugin(() => concealedRanges(window.editor)),
  EditorView.atomicRanges.of(view => {
    try {
      return concealedRanges(view);
    } catch {
      return RangeSet.empty;
    }
  }),
  tablePreviewField,
  EditorView.atomicRanges.of(view => view.state.field(tablePreviewField)),
];
