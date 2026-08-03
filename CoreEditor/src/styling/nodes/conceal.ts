import { Decoration } from '@codemirror/view';
import { Range } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { createDecoPlugin } from '../helper';

const hiddenDeco = Decoration.replace({});

/**
 * Live-preview concealment: replaces markdown syntax marks with nothing,
 * everywhere — including the cursor line. View-layer only — the
 * document, undo, search, and copy are untouched.
 */
export const concealExtension = createDecoPlugin(() => {
  const editor = window.editor;
  const state = editor.state;

  const ranges: Range<Decoration>[] = [];
  const conceal = (from: number, to: number) => {
    ranges.push(hiddenDeco.range(from, to));
  };

  for (const { from, to } of editor.visibleRanges) {
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
});
