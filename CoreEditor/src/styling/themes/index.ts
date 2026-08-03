import { EditorTheme } from '../types';

import GitHubLight from './github-light';
import GitHubDark from './github-dark';
import MinimalLight from './minimal-light';
import MinimalDark from './minimal-dark';

const themes: { [key: string]: (() => EditorTheme) | undefined } = {
  'github-light': GitHubLight,
  'github-dark': GitHubDark,
  'minimal-light': MinimalLight,
  'minimal-dark': MinimalDark,
};

export function loadTheme(name: string): EditorTheme {
  return (themes[name] ?? GitHubLight)();
}

export type { EditorTheme };
