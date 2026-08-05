import { Decoration, DecorationSet, lineNumbers } from '@codemirror/view';
import { codeFolding, foldState } from '@codemirror/language';

// No foldGutter: numbers sit bare on the canvas, folding stays command-driven
export const gutterExtensions = [
  lineNumbers(),
  codeFolding({ placeholderText: '•••' }),
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
