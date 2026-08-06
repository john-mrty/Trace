import { syntaxTree } from '@codemirror/language';
import { EditorState } from '@codemirror/state';
import { SyntaxNode } from '@lezer/common';

/**
 * Render the selection (or the whole document when nothing is selected)
 * as semantic HTML, and write both html and plain-text flavors to the clipboard.
 *
 * The plain flavor is the Markdown source, matching a regular copy.
 */
export async function copyAsRichText() {
  const state = window.editor.state;
  const { from, to } = state.selection.main;
  const range = from === to ? { from: 0, to: state.doc.length } : { from, to };
  const html = renderRangeAsHTML(state, range.from, range.to);
  const plain = state.sliceDoc(range.from, range.to);

  try {
    await navigator.clipboard.write([
      new ClipboardItem({
        'text/html': new Blob([html], { type: 'text/html' }),
        'text/plain': new Blob([plain], { type: 'text/plain' }),
      }),
    ]);
  } catch {
    await navigator.clipboard.writeText(plain);
  }
}

export function renderRangeAsHTML(state: EditorState, from: number, to: number): string {
  return renderChildren(syntaxTree(state).topNode, state, from, to);
}

// Syntax-only nodes whose text never appears in the output
const hiddenNodes = new Set([
  'HeaderMark', 'QuoteMark', 'ListMark', 'EmphasisMark', 'CodeMark',
  'StrikethroughMark', 'LinkMark', 'TaskMarker', 'CodeInfo', 'TableDelimiter',
  'LinkTitle', 'LinkLabel', 'Frontmatter', 'CommentBlock', 'LinkReference',
]);

const inlineTags = new Map([
  ['Emphasis', 'em'],
  ['StrongEmphasis', 'strong'],
  ['Strikethrough', 'del'],
  ['InlineCode', 'code'],
]);

// Containers whose direct text (newlines, pipes, indentation) is structural noise
const blockContainers = new Set([
  'Document', 'Blockquote', 'BulletList', 'OrderedList', 'ListItem',
  'Table', 'TableHeader', 'TableRow', 'FencedCode', 'CodeBlock',
]);

function renderNode(node: SyntaxNode, state: EditorState, from: number, to: number): string {
  const name = node.name;
  if (hiddenNodes.has(name)) {
    return '';
  }

  const headingLevel = /^ATXHeading(\d)$/.exec(name)?.[1];
  if (headingLevel !== undefined) {
    return `<h${headingLevel}>${renderChildren(node, state, from, to).trim()}</h${headingLevel}>\n`;
  }

  switch (name) {
    case 'Paragraph':
    case 'Task': {
      const inner = taskListPrefix(node, state) + renderChildren(node, state, from, to).trim();
      // Tight list items paste better without paragraph spacing
      return node.parent?.name === 'ListItem' ? inner : `<p>${inner}</p>\n`;
    }
    case 'Blockquote':
      return `<blockquote>\n${renderChildren(node, state, from, to)}</blockquote>\n`;
    case 'BulletList':
      return `<ul>\n${renderChildren(node, state, from, to)}</ul>\n`;
    case 'OrderedList': {
      const start = /^(\d+)/.exec(firstChildText(node, 'ListMark', state))?.[1];
      const attr = start !== undefined && start !== '1' ? ` start="${start}"` : '';
      return `<ol${attr}>\n${renderChildren(node, state, from, to)}</ol>\n`;
    }
    case 'ListItem':
      return `<li>${renderChildren(node, state, from, to)}</li>\n`;
    case 'FencedCode':
    case 'CodeBlock': {
      const code = node.getChildren('CodeText')
        .map(child => sliceText(state, child.from, child.to, from, to))
        .join('');
      return `<pre><code>${escapeHTML(code)}</code></pre>\n`;
    }
    case 'HorizontalRule':
      return '<hr>\n';
    case 'Table':
      return `<table>\n${renderChildren(node, state, from, to)}</table>\n`;
    case 'TableHeader':
    case 'TableRow': {
      const tag = name === 'TableHeader' ? 'th' : 'td';
      const cells = node.getChildren('TableCell')
        .map(cell => `<${tag}>${renderChildren(cell, state, from, to)}</${tag}>`)
        .join('');
      return `<tr>${cells}</tr>\n`;
    }
    case 'Link': {
      const href = linkDestination(node, state);
      const label = renderChildren(node, state, from, to);
      return href === undefined ? label : `<a href="${escapeAttr(href)}">${label}</a>`;
    }
    case 'Image': {
      const src = linkDestination(node, state);
      const alt = plainChildText(node, state);
      return src === undefined ? '' : `<img src="${escapeAttr(src)}" alt="${escapeAttr(alt)}">`;
    }
    case 'URL': {
      // Autolinks; URL nodes inside Link/Image are consumed by their parent
      const url = state.sliceDoc(node.from, node.to);
      return `<a href="${escapeAttr(url)}">${escapeHTML(url)}</a>`;
    }
    case 'HardBreak':
      return '<br>';
    case 'Escape':
      return escapeHTML(state.sliceDoc(node.from + 1, node.to));
    case 'Entity':
    case 'HTMLTag':
    case 'HTMLBlock':
      return sliceText(state, node.from, node.to, from, to);
    default: {
      const tag = inlineTags.get(name);
      const inner = renderChildren(node, state, from, to);
      return tag === undefined ? inner : `<${tag}>${inner}</${tag}>`;
    }
  }
}

function renderChildren(node: SyntaxNode, state: EditorState, from: number, to: number): string {
  const pieces: string[] = [];
  const emitGaps = !blockContainers.has(node.name);
  let pos = node.from;

  for (let child = node.firstChild; child !== null; child = child.nextSibling) {
    if (emitGaps && child.from > pos) {
      pieces.push(escapeHTML(sliceText(state, pos, child.from, from, to)));
    }

    if (child.name === 'URL' && (node.name === 'Link' || node.name === 'Image')) {
      pos = child.to;
      continue;
    }

    if (child.from < to && child.to > from) {
      pieces.push(renderNode(child, state, from, to));
    }

    pos = child.to;
  }

  if (emitGaps && node.to > pos) {
    pieces.push(escapeHTML(sliceText(state, pos, node.to, from, to)));
  }

  return pieces.join('');
}

function taskListPrefix(node: SyntaxNode, state: EditorState): string {
  const marker = node.getChild('TaskMarker');
  if (marker === null || node.parent?.name !== 'ListItem') {
    return '';
  }

  return /[xX]/.test(state.sliceDoc(marker.from, marker.to)) ? '☑ ' : '☐ ';
}

function linkDestination(node: SyntaxNode, state: EditorState): string | undefined {
  const url = node.getChildren('URL').pop();
  if (url === undefined) {
    return undefined;
  }

  const text = state.sliceDoc(url.from, url.to);
  return text.startsWith('<') && text.endsWith('>') ? text.slice(1, -1) : text;
}

function plainChildText(node: SyntaxNode, state: EditorState): string {
  const open = node.getChildren('LinkMark').at(1);
  const start = node.firstChild;
  if (open === undefined || start === null) {
    return '';
  }

  return state.sliceDoc(start.to, open.from);
}

function firstChildText(node: SyntaxNode, childName: string, state: EditorState): string {
  const item = node.getChild('ListItem');
  const mark = item?.getChild(childName);
  return mark === null || mark === undefined ? '' : state.sliceDoc(mark.from, mark.to);
}

function sliceText(state: EditorState, from: number, to: number, clampFrom: number, clampTo: number): string {
  const start = Math.max(from, clampFrom);
  const end = Math.min(to, clampTo);
  return start >= end ? '' : state.sliceDoc(start, end);
}

function escapeHTML(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escapeAttr(text: string): string {
  return escapeHTML(text).replace(/"/g, '&quot;');
}
