import { describe, expect, test } from '@jest/globals';
import { EditorSelection } from '@codemirror/state';
import { concealExtension } from '../src/styling/nodes/conceal';
import { sleep } from './utils/helpers';
import * as editor from './utils/editor';

const doc = '# Title\n\n**bold** and `code` and ~~gone~~ [text](https://example.com)\n';

function contentText() {
  return document.querySelector('.cm-content')?.textContent ?? '';
}

describe('Conceal syntax marks', () => {
  test('hides marks except on selected lines', async () => {
    editor.setUp(doc, concealExtension);
    await sleep(200);

    // Cursor starts at 0 → line 1 is active, its marks stay revealed
    expect(contentText()).toContain('# Title');

    // Line 3 is not selected → all inline marks concealed
    expect(contentText()).not.toContain('**');
    expect(contentText()).not.toContain('`');
    expect(contentText()).not.toContain('~~');
    expect(contentText()).not.toContain('https://example.com');
    expect(contentText()).not.toContain('[text]');
    expect(contentText()).toContain('bold and code and gone text');

    // Move cursor to line 3 → its marks reveal, heading conceals
    window.editor.dispatch({ selection: EditorSelection.cursor(doc.indexOf('**bold**')) });
    await sleep(200);
    expect(contentText()).toContain('**bold**');
    expect(contentText()).toContain('[text](https://example.com)');
    expect(contentText()).not.toContain('# Title');
    expect(contentText()).toContain('Title');
  });
});
