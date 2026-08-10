import { Decoration, DecorationSet, EditorView, lineNumbers, ViewPlugin, ViewUpdate } from '@codemirror/view';
import { codeFolding, foldState } from '@codemirror/language';

// 3-digit line numbers don't fit the standard 48px margin; flag 100+ line
// documents so the theme can widen the gutter (see .cm-md-wideGutters)
const wideGuttersPlugin = ViewPlugin.define(view => {
  const sync = (target: EditorView) => {
    target.dom.classList.toggle('cm-md-wideGutters', target.state.doc.lines > 99);
  };

  sync(view);
  return {
    update(update: ViewUpdate) {
      if (update.docChanged) {
        sync(update.view);
      }
    },
  };
});

// No foldGutter: numbers sit bare on the canvas, folding stays command-driven
export const gutterExtensions = [
  lineNumbers(),
  codeFolding({ placeholderText: '•••' }),
  wideGuttersPlugin,
];

export function isPositionFolded(pos: number) {
  let rangeSet: DecorationSet = Decoration.none;
  let isFolded = false;

  try {
    rangeSet = window.editor.state.field(foldState);
  } catch (error) {
    console.error(error);
    return false;
  }

  rangeSet.between(pos, pos, (from, to) => {
    if (pos >= from && pos < to) {
      isFolded = true;
      return false;
    }
  });

  return isFolded;
}
