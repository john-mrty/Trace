# Hide Markdown Syntax Marks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persisted toggle (NSToolbar + overlay FAB) that conceals markdown syntax marks view-side, with reveal-on-active-line, so documents read like rendered text while staying editable.

**Architecture:** A CodeMirror view plugin (`Decoration.replace` over syntax-tree mark nodes, skipping selection lines) gated by a new `conceal` compartment. A `hideSyntaxMarks` boolean flows Swift→web exactly like the existing `typewriterMode`: `EditorConfig` field for initial load + `setHideSyntaxMarks` web-bridge method for live toggling. Spec: `docs/superpowers/specs/2026-08-03-hide-syntax-marks-design.md`.

**Tech Stack:** CoreEditor (TypeScript, CodeMirror 6, jest/jsdom, ts-gyb codegen), MarkEditMac (Swift/AppKit).

## Global Constraints

- Repo: `~/src/MarkEdit`, branch `johnmoriarty/polish-and-overlay`. All paths below relative to repo root.
- NEVER run `xcodebuild` (hangs in this environment). Verify Swift with `swiftlint lint --config .swiftlint.yml <files>` (brew swiftlint 0.65.0) and `xcrun swiftc -parse <file>` (syntax only; cross-module type errors surface at human ⌘R).
- CoreEditor changes require `cd CoreEditor && yarn build` (runs eslint + ts-gyb codegen + vite). Codegen REWRITES generated Swift under `MarkEditCore/Sources` and `MarkEditKit/Sources/Bridge/Web/Generated` — always commit those alongside the TS change.
- No new Swift files anywhere in this plan (avoids manual pbxproj registration). Only existing files are modified.
- SwiftLint: `type_body_length` 250 — new Swift code goes in the extension files named below, not `EditorViewController.swift` / `EditorWindow.swift` class bodies.
- Keep comments minimal; 2–3 lines max when a non-obvious reason needs recording.

---

### Task 1: Conceal extension (TS) with jest tests

**Files:**
- Create: `CoreEditor/src/styling/nodes/conceal.ts`
- Test: `CoreEditor/test/conceal.test.ts`

**Interfaces:**
- Consumes: `createDecoPlugin` from `src/styling/helper.ts` (builder runs on every view update, so selection changes recompute automatically); `window.editor` / `window.config` globals.
- Produces: `export const concealExtension` — a CodeMirror `Extension`. Task 2 wires it into a compartment.

- [ ] **Step 1: Write the failing test**

Create `CoreEditor/test/conceal.test.ts`:

```ts
import { describe, expect, test } from '@jest/globals';
import { EditorSelection } from '@codemirror/state';
import { concealExtension } from '../src/styling/nodes/conceal';
import { sleep } from './utils/helpers';
import * as editor from './utils/editor';

const doc = '# Title\n\n**bold** and `code` and ~~gone~~ [text](https://example.com)\n';

function contentText() {
  return (document.querySelector('.cm-content') as HTMLElement).textContent ?? '';
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd CoreEditor && yarn test test/conceal.test.ts`
Expected: FAIL — cannot find module `../src/styling/nodes/conceal`

- [ ] **Step 3: Write the implementation**

Create `CoreEditor/src/styling/nodes/conceal.ts`:

```ts
import { Decoration } from '@codemirror/view';
import { Range } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { createDecoPlugin } from '../helper';

const hiddenDeco = Decoration.replace({});

/**
 * Live-preview concealment: replaces markdown syntax marks with nothing,
 * except on lines intersecting the selection. View-layer only — the
 * document, undo, search, and copy are untouched.
 */
export const concealExtension = createDecoPlugin(() => {
  const editor = window.editor;
  const state = editor.state;

  const selectedLines = new Set<number>();
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let line = first; line <= last; ++line) {
      selectedLines.add(line);
    }
  }

  const ranges: Range<Decoration>[] = [];
  const conceal = (from: number, to: number) => {
    if (!selectedLines.has(state.doc.lineAt(from).number)) {
      ranges.push(hiddenDeco.range(from, to));
    }
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd CoreEditor && yarn test test/conceal.test.ts`
Expected: PASS. Also run `yarn test` (full suite) — no regressions.

- [ ] **Step 5: Lint and commit**

```bash
cd CoreEditor && yarn lint
cd .. && git add CoreEditor/src/styling/nodes/conceal.ts CoreEditor/test/conceal.test.ts
git commit -m "Conceal: view-layer hiding of markdown syntax marks"
```

---

### Task 2: Config flag, compartment, and web bridge (TS + codegen)

**Files:**
- Modify: `CoreEditor/src/config.ts` (Config interface ~line 68; Dynamics interface below it)
- Modify: `CoreEditor/src/extensions.ts` (compartments ~line 43-60; extension list ~line 159)
- Modify: `CoreEditor/src/styling/config.ts` (after `setTypewriterMode`, ~line 136)
- Modify: `CoreEditor/src/modules/config/index.ts` (after `setTypewriterMode`, ~line 83)
- Modify: `CoreEditor/src/bridge/web/config.ts` (interface ~line 36, impl ~line 75)
- Regenerated by `yarn build` (commit them): `MarkEditCore/Sources/*.swift`, `MarkEditKit/Sources/Bridge/Web/Generated/WebBridgeConfig.swift`

**Interfaces:**
- Consumes: `concealExtension` from Task 1.
- Produces: `window.config.hideSyntaxMarks: boolean`; `window.dynamics.conceal` compartment; web-bridge method `setHideSyntaxMarks({ enabled: boolean })`. After codegen: Swift `EditorConfig` gains a `hideSyntaxMarks: Bool` init parameter positioned right after `typewriterMode`, and `WebBridgeConfig` gains `setHideSyntaxMarks(enabled: Bool)`. Tasks 3–4 rely on both.

- [ ] **Step 1: Add the config field and compartment slot**

In `CoreEditor/src/config.ts`, immediately after `typewriterMode: boolean;`:

```ts
  hideSyntaxMarks: boolean;
```

In the `Dynamics` interface (same file), after the last compartment entry:

```ts
  conceal?: Compartment;
```

- [ ] **Step 2: Wire the compartment in extensions.ts**

In `CoreEditor/src/extensions.ts`:
- Add import: `import { concealExtension } from './styling/nodes/conceal';`
- With the other compartments (~line 53): `const conceal = new Compartment;`
- Add `conceal,` to the `window.dynamics`/exported compartment object alongside `invisibles,`.
- In the extension array, directly after the `selectedLines.of(...)` line:

```ts
    conceal.of(window.config.hideSyntaxMarks ? concealExtension : []),
```

- [ ] **Step 3: Add the runtime setters**

`CoreEditor/src/styling/config.ts`, after `setTypewriterMode` (add `concealExtension` to imports from `./nodes/…` — new import line `import { concealExtension } from './nodes/conceal';`):

```ts
export function setHideSyntaxMarks(enabled: boolean) {
  window.editor.dispatch({
    effects: window.dynamics.conceal?.reconfigure(enabled ? concealExtension : []),
  });
}
```

`CoreEditor/src/modules/config/index.ts`, after `setTypewriterMode`:

```ts
export function setHideSyntaxMarks(enabled: boolean) {
  window.config.hideSyntaxMarks = enabled;
  styling.setHideSyntaxMarks(enabled);
}
```

- [ ] **Step 4: Expose the web-bridge method**

`CoreEditor/src/bridge/web/config.ts` — three edits mirroring `setTypewriterMode` exactly:
- Add `setHideSyntaxMarks,` to the import list from `../../modules/config`.
- In `interface WebModuleConfig`, after the `setTypewriterMode` declaration:

```ts
  setHideSyntaxMarks({ enabled }: { enabled: boolean }): void;
```

- In the implementation object, after the `setTypewriterMode` method:

```ts
  setHideSyntaxMarks({ enabled }: { enabled: boolean }): void {
    setHideSyntaxMarks(enabled);
  },
```

- [ ] **Step 5: Build (lint + codegen + bundle) and verify codegen output**

Run: `cd CoreEditor && yarn build`
Expected: clean build ending `✓ built in …`.

Run: `cd .. && git diff --stat MarkEditCore MarkEditKit`
Expected: the generated `EditorConfig` Swift file shows a new `hideSyntaxMarks: Bool` property/init param right after `typewriterMode`; `WebBridgeConfig.swift` shows a new `setHideSyntaxMarks(enabled: Bool)` method. The macOS app will NOT compile until Task 3 passes the new init argument — expected mid-stack state.

Run: `cd CoreEditor && yarn test`
Expected: PASS (full suite).

- [ ] **Step 6: Commit**

```bash
git add CoreEditor/src MarkEditCore MarkEditKit
git commit -m "Conceal: hideSyntaxMarks config flag + web bridge method"
```

---

### Task 3: Swift preference and config plumbing

**Files:**
- Modify: `MarkEditMac/Sources/Main/AppPreferences.swift` (Editor enum ~line 122; `editorConfig` builder ~line 286)
- Modify: `MarkEditMac/Sources/Editor/Controllers/EditorViewController+Config.swift` (~line 78)

**Interfaces:**
- Consumes: generated `EditorConfig(… hideSyntaxMarks:…)` init and `bridge.config.setHideSyntaxMarks(enabled:)` from Task 2.
- Produces: `AppPreferences.Editor.hideSyntaxMarks: Bool` (persisted; didSet pushes to all editors) and `EditorViewController.setHideSyntaxMarks(enabled:)`. Task 4 flips the preference and calls the refresh hooks added there.

- [ ] **Step 1: Add the persisted preference**

In `MarkEditMac/Sources/Main/AppPreferences.swift`, inside `enum Editor`, directly after the `typewriterMode` property:

```swift
    @Storage(key: "editor.hide-syntax-marks", defaultValue: false)
    static var hideSyntaxMarks: Bool {
      didSet {
        performUpdates { $0.setHideSyntaxMarks(enabled: hideSyntaxMarks) }
      }
    }
```

- [ ] **Step 2: Pass it in the initial EditorConfig**

Same file, in the `editorConfig` construction (~line 286), directly after `typewriterMode: Editor.typewriterMode,` (argument position must match the generated init order):

```swift
      hideSyntaxMarks: Editor.hideSyntaxMarks,
```

- [ ] **Step 3: Add the view-controller setter**

In `MarkEditMac/Sources/Editor/Controllers/EditorViewController+Config.swift`, after `setTypewriterMode`:

```swift
  func setHideSyntaxMarks(enabled: Bool) {
    bridge.config.setHideSyntaxMarks(enabled: enabled)
    updateHideSyntaxMarksToolbarIcon()
    (view.window as? EditorWindow)?.overlayFab?.refreshButtonImages()
  }
```

Note: `updateHideSyntaxMarksToolbarIcon()` and `refreshButtonImages()` are defined in Task 4. If Task 3 is verified standalone, stub nothing — verify with Task 4 applied, or temporarily comment the two lines out for `swiftc -parse` only.

- [ ] **Step 4: Verify**

```bash
swiftlint lint --config .swiftlint.yml MarkEditMac/Sources/Main/AppPreferences.swift MarkEditMac/Sources/Editor/Controllers/EditorViewController+Config.swift
xcrun swiftc -parse MarkEditMac/Sources/Editor/Controllers/EditorViewController+Config.swift 2>&1 | grep -v "no such module\|error: cannot find" || true
```
Expected: zero SwiftLint violations; only cross-module resolution noise from `swiftc -parse`.

- [ ] **Step 5: Commit**

```bash
git add MarkEditMac/Sources/Main/AppPreferences.swift MarkEditMac/Sources/Editor/Controllers/EditorViewController+Config.swift
git commit -m "Conceal: persisted hideSyntaxMarks preference + editor plumbing"
```

---

### Task 4: Toolbar item + stateful FAB button

**Files:**
- Modify: `MarkEditMac/Sources/Main/AppResources.swift` (Localized.Toolbar strings ~line 53; Icons ~line 251)
- Modify: `MarkEditMac/Sources/Editor/Models/EditorToolbarItems.swift` (identifier list, `defaultItems`, `allItems`, `itemLabel`, `itemIcon`)
- Modify: `MarkEditMac/Sources/Editor/Controllers/EditorViewController+Toolbar.swift` (item accessor + switch case + icon refresh + toggle action)
- Modify: `MarkEditMac/Sources/Editor/EditorOverlayToolbar.swift` (stateful Action support)
- Modify: `MarkEditMac/Sources/Editor/EditorWindow+Overlay.swift` (sixth FAB action)
- Modify: `MarkEditMac/Sources/Editor/EditorWindow.swift` (icon refresh after toolbar restore)

**Interfaces:**
- Consumes: `AppPreferences.Editor.hideSyntaxMarks` (Task 3); existing `NSToolbarItem.with(identifier:iconSize:action:)`, `NSImage.with(symbolName:pointSize:…)`, `OverlayIconButton` internals.
- Produces: `EditorViewController.toggleHideSyntaxMarks(_:)` and `.updateHideSyntaxMarksToolbarIcon()`; `EditorOverlayToolbar.refreshButtonImages()`; `EditorOverlayToolbar.Action.currentSymbolName: (() -> String)?` (defaulted, so existing five actions compile unchanged).

- [ ] **Step 1: Strings and icons**

`AppResources.swift` — in `Localized.Toolbar` (alphabetical/nearby placement with the other toolbar strings):

```swift
    static let hideSyntaxMarks = String(localized: "Hide Markdown", comment: "Toolbar item to hide Markdown syntax marks")
```

In the `Icons` enum (plain constants section ~line 251):

```swift
  static let eye = "eye"
  static let eyeSlash = "eye.slash"
```

- [ ] **Step 2: Register the toolbar identifier**

`EditorToolbarItems.swift`:
- After `static let writingTools = newItem("writingTools")`:

```swift
  static let hideSyntaxMarks = newItem("hideSyntaxMarks")
```

- In `defaultItems`, append `.hideSyntaxMarks` after `.toggleList`.
- In `allItems`, insert `.hideSyntaxMarks` after `.insertCode`.
- In `itemLabel`: `case .hideSyntaxMarks: return Localized.Toolbar.hideSyntaxMarks`
- In `itemIcon`: `case .hideSyntaxMarks: return AppPreferences.Editor.hideSyntaxMarks ? Icons.eyeSlash : Icons.eye`

- [ ] **Step 3: Toolbar item, toggle action, icon refresh**

`EditorViewController+Toolbar.swift`:
- In the `itemForItemIdentifier` switch, before `default:`: `case .hideSyntaxMarks: return hideSyntaxMarksItem`
- With the other item accessors:

```swift
  var hideSyntaxMarksItem: NSToolbarItem {
    .with(identifier: .hideSyntaxMarks, iconSize: Constants.normalizedButtonSize) {
      AppPreferences.Editor.hideSyntaxMarks.toggle()
    }
  }
```

(The preference's `didSet` fans out to every editor via `performUpdates`, which calls `setHideSyntaxMarks(enabled:)` — that's where UI refresh happens; the action itself only flips state.)

- Add the icon refresh used by `setHideSyntaxMarks`:

```swift
  func updateHideSyntaxMarksToolbarIcon() {
    guard let item = view.window?.toolbar?.items.first(where: { $0.itemIdentifier == .hideSyntaxMarks }) else {
      return
    }

    item.image = .with(
      symbolName: AppPreferences.Editor.hideSyntaxMarks ? Icons.eyeSlash : Icons.eye,
      pointSize: Constants.normalizedButtonSize,
      accessibilityLabel: item.label
    )
  }
```

- Also add an `@objc` passthrough for the FAB (place near the other toolbar-forwarded actions):

```swift
  @objc func toggleHideSyntaxMarks(_ sender: Any?) {
    AppPreferences.Editor.hideSyntaxMarks.toggle()
  }
```

- [ ] **Step 4: Stateful FAB actions**

`EditorOverlayToolbar.swift`:
- Extend `Action` (defaulted property keeps the five existing initializer calls compiling):

```swift
  struct Action {
    let symbolName: String
    let accessibilityLabel: String
    var currentSymbolName: (() -> String)? = nil
    let handler: (NSButton) -> Void
  }
```

- In `setUpButtons()`, resolve the symbol via `action.currentSymbolName?() ?? action.symbolName` when building `button.image`.
- Add (non-private, called from `EditorViewController+Config.swift`):

```swift
  func refreshButtonImages() {
    for (index, action) in actions.enumerated() {
      guard let provider = action.currentSymbolName, buttons.indices.contains(index) else {
        continue
      }

      buttons[index].image = .with(
        symbolName: provider(),
        pointSize: Constants.iconPointSize,
        weight: .medium,
        accessibilityLabel: action.accessibilityLabel
      )
    }
  }
```

Note: `Constants` lives in the private extension; `refreshButtonImages()` must be declared inside the main class body or a non-private extension in the same file (same-file access to `private extension` members is allowed in Swift — keep it in this file).

- [ ] **Step 5: Sixth FAB action + toolbar-restore refresh**

`EditorWindow+Overlay.swift`, append to the array in `overlayFabActions(for:)`:

```swift
      EditorOverlayToolbar.Action(
        symbolName: Icons.eye,
        accessibilityLabel: Localized.Toolbar.hideSyntaxMarks,
        currentSymbolName: { AppPreferences.Editor.hideSyntaxMarks ? Icons.eyeSlash : Icons.eye }
      ) { [weak viewController] _ in
        viewController?.toggleHideSyntaxMarks(nil)
      },
```

`EditorWindow.swift`, in `toolbarMode`'s `didSet` (after `updateTitleBarAppearance()`), so an overlay-mode toggle isn't stale when the real toolbar comes back:

```swift
      (contentViewController as? EditorViewController)?.updateHideSyntaxMarksToolbarIcon()
```

- [ ] **Step 6: Verify**

```bash
swiftlint lint --config .swiftlint.yml MarkEditMac/Sources/Main/AppResources.swift MarkEditMac/Sources/Editor/Models/EditorToolbarItems.swift MarkEditMac/Sources/Editor/Controllers/EditorViewController+Toolbar.swift MarkEditMac/Sources/Editor/EditorOverlayToolbar.swift MarkEditMac/Sources/Editor/EditorWindow+Overlay.swift MarkEditMac/Sources/Editor/EditorWindow.swift
```
Expected: zero violations (watch `type_body_length` on EditorWindow.swift — the didSet addition is one line, safe).

`xcrun swiftc -parse` each modified file; expect only cross-module noise.

- [ ] **Step 7: Commit**

```bash
git add MarkEditMac/Sources/Main/AppResources.swift MarkEditMac/Sources/Editor/Models/EditorToolbarItems.swift MarkEditMac/Sources/Editor/Controllers/EditorViewController+Toolbar.swift MarkEditMac/Sources/Editor/EditorOverlayToolbar.swift MarkEditMac/Sources/Editor/EditorWindow+Overlay.swift MarkEditMac/Sources/Editor/EditorWindow.swift
git commit -m "Conceal: eye toggle in toolbar + overlay FAB"
```

---

### Human QA checklist (after ⌘R)

1. Toolbar eye toggle: `# `, `**`, `*`, `~~`, backticks, `[..](url)` concealed; cursor line reveals; icon flips eye↔eye.slash.
2. Links: only styled text visible; clicking/caret movement around concealed spans behaves (no drift/dead zones).
3. Fenced code blocks, images `![](…)`, tables unchanged.
4. Toggle in overlay FAB; exit overlay → NSToolbar icon matches state.
5. Two windows open: toggling in one updates the other live.
6. Relaunch: state persists and applies on load.
7. Full jest suite + `yarn build` clean (already gated per task).
