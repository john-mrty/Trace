import { Decoration, EditorView, WidgetType } from '@codemirror/view';
import { Range, RangeSet } from '@codemirror/state';
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
export const concealExtension = [
  createDecoPlugin(() => concealedRanges(window.editor)),
  EditorView.atomicRanges.of(view => {
    try {
      return concealedRanges(view);
    } catch {
      return RangeSet.empty;
    }
  }),
];
