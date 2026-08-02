import { BlockWrapper, Decoration, DOMEventHandlers, EditorView, ViewPlugin } from '@codemirror/view';
import { Range, RangeSet } from '@codemirror/state';
import { globalState } from '../common/store';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function createBlockPlugin(builder: () => RangeSet<BlockWrapper>, eventHandlers?: DOMEventHandlers<any>) {
  return ViewPlugin.fromClass(class {}, {
    provide: () => EditorView.blockWrappers.of(editor => {
      window.editor = editor;
      try {
        return builder();
      } catch (error) {
        console.error(error);
        return RangeSet.empty;
      }
    }),
    eventHandlers,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function createDecoPlugin(builder: () => RangeSet<Decoration>, eventHandlers?: DOMEventHandlers<any>) {
  return ViewPlugin.fromClass(class {}, {
    provide: () => EditorView.decorations.of(editor => {
      window.editor = editor;
      try {
        return builder();
      } catch (error) {
        console.error(error);
        return Decoration.none;
      }
    }),
    eventHandlers,
  });
}

/**
 * Get line deco ranges for a text range, which can be multiple lines.
 */
export function lineDecoRanges(from: number, to: number, className: string, attributes?: { [key: string]: string }) {
  const doc = window.editor.state.doc;
  const decos: Range<Decoration>[] = [];
  const start = doc.lineAt(from).number;
  const end = doc.lineAt(to).number;

  // Generate the range for each line
  for (let index = start; index <= end; ++index) {
    const line = doc.line(index);
    const deco = Decoration.line({ class: className, attributes });
    decos.push(deco.range(line.from, line.from));
  }

  // Ranges are already sorted
  return decos;
}

export function updateStyleSheet(element: HTMLStyleElement | null, update: (style: CSSStyleDeclaration, rule: CSSStyleRule) => void) {
  const rules = element?.sheet?.cssRules;
  if (rules === undefined) {
    return;
  }

  for (let index = 0; index < rules.length; ++index) {
    const rule = rules[index] as CSSStyleRule;
    update(rule.style as CSSStyleDeclaration, rule);
  }
}

/**
 * Returns a css style in { 'color': foo, 'text-shadow': bar } format from a css string like "color: foo; text-shadow: bar".
 *
 * Note that, the input string must exactly follow the format, this is not an error-tolerant approach.
 */
export function shadowableTextColor(input: string) {
  if (!input.includes('; ')) {
    return { 'color': input, 'text-shadow': 'none' };
  }

  const style: { [key: string]: string } = {};
  return input.split('; ').reduce((acc, cur) => {
    const parts = cur.split(': ');
    acc[parts[0]] = parts[1];
    return acc;
  }, style);
}

/**
 * Blend a hex color with a translucent alpha so the native backdrop shows through.
 *
 * WebKit supports color-mix(); percentage is the opacity of the original color.
 */
export function translucentBackground(hexColor: string, opacity: number) {
  return `color-mix(in srgb, ${hexColor} ${Math.round(opacity * 100)}%, transparent)`;
}

/**
 * Notify native of the current theme background color.
 *
 * The web side may paint a translucent version of this color (see `translucentBackground`)
 * so the native backdrop blur shows through, but native must keep receiving the opaque
 * theme color, since it uses this to draw the real window/backdrop base. So we prefer
 * the source-of-truth `globalState.colors.background` over reading the (possibly
 * translucent) computed style off the DOM.
 */
export function notifyBackgroundColor(inputColor?: string) {
  const color = inputColor ?? globalState.colors?.background ?? getComputedStyle(window.editor.dom).backgroundColor;
  const hexMatch = color.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);

  if (hexMatch !== null) {
    const code = parseInt(`${hexMatch[1]}${hexMatch[2]}${hexMatch[3]}`, 16) as CodeGen_Int;
    window.nativeModules.core.notifyBackgroundColorDidChange({ color: code, alpha: 1.0 });
    return;
  }

  const match = color.match(/rgba?\(\s*(\d+),\s*(\d+),\s*(\d+)(?:,\s*(\d*\.?\d+))?\s*\)/);
  if (match === null) {
    return console.error(`Invalid background color: ${color}`);
  }

  const toHex = (value: string) => parseInt(value).toString(16).padStart(2, '0');
  const red = toHex(match[1]), green = toHex(match[2]), blue = toHex(match[3]);

  // Change it back to number because we only have parsers to handle numbers in native
  const code = parseInt(`${red}${green}${blue}`, 16) as CodeGen_Int;
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  const alpha = parseFloat(match[4] ?? '1.0');

  window.nativeModules.core.notifyBackgroundColorDidChange({
    color: code,
    alpha,
  });
}
