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
  test('hides marks everywhere, including the cursor line', async () => {
    editor.setUp(doc, concealExtension);
    await sleep(200);

    expect(contentText()).not.toContain('#');
    expect(contentText()).toContain('Title');
    expect(contentText()).not.toContain('**');
    expect(contentText()).not.toContain('`');
    expect(contentText()).not.toContain('~~');
    expect(contentText()).not.toContain('https://example.com');
    expect(contentText()).not.toContain('[text]');
    expect(contentText()).toContain('bold and code and gone text');

    // Moving the cursor onto a marked line changes nothing — still concealed
    window.editor.dispatch({ selection: EditorSelection.cursor(doc.indexOf('**bold**')) });
    await sleep(200);
    expect(contentText()).not.toContain('**');
    expect(contentText()).not.toContain('#');
    expect(contentText()).toContain('Title');
  });
});
