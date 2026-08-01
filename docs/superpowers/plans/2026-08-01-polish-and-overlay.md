# MarkEdit Polish + Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a personal MarkEdit fork subtle window translucency, more refined Markdown/UI typography, and an Option+` quick-summon overlay that slides in from the right edge over other apps.

**Architecture:** Three independent workstreams. A (translucency) and B (typography) are material/CSS tuning of existing abstractions. C (overlay) repurposes the existing global-hotkey + document-window-toggle path (`AppDelegate` / `AppDelegate+Document`) by adding an `overlayMode` to `EditorWindow` — the overlay *is* the document window repositioned, not a new panel.

**Tech Stack:** Swift/AppKit (`MarkEditMac`), WKWebView + CodeMirror 6 (`CoreEditor`, TypeScript/CSS), Carbon global hotkeys, Xcode 26 / Node 25 / Yarn 4.

## Global Constraints

- macOS 15+ (repo requirement); use `#available` guards for macOS 26 `NSGlassEffectView` paths, mirroring `AppDesign.modernEffectView`.
- Translucency must honour `AppDesign.reduceTransparency` (pref OR system accessibility flag) → fall back opaque.
- Overlay animation must honour `AppDesign.reduceMotion` → no animation when set.
- Overlay hotkey is **Option+`** only. Do NOT touch Ctrl+` (Ghostty) or the existing `mainWindowHotKey`.
- Editor colour themes (`CoreEditor/src/styling/themes/`) are not modified.
- Editor changes require `cd CoreEditor && yarn build` to land in `dist/index.html`; the macOS app then picks it up on Xcode build.
- Branch: `johnmoriarty/polish-and-overlay`. Commit after each task. No push (read-only upstream clone).

---

## Task 1: Window translucency (all editor windows)

**Files:**
- Modify: `MarkEditMac/Sources/Editor/Controllers/EditorViewController.swift` (add a full-size backdrop `MaterialView` behind the web view; make the web view transparent)
- Modify: `MarkEditMac/Sources/Editor/EditorWindow.swift` (`isOpaque = false`, clear background when translucent)
- Modify: `CoreEditor/index.css` (transparent body / `.cm-editor` background)

**Interfaces:**
- Produces: `EditorViewController.backdropView: MaterialView` (full-bleed, behind web view); relies on existing `AppDesign.modernEffectView` and `AppDesign.reduceTransparency`.

- [ ] **Step 1: Make the CodeMirror surface transparent**

In `CoreEditor/index.css`, change the `html, body` and `.cm-editor` blocks so the web layer stops painting an opaque background (the native material shows through; the theme still colours text/selection):

```css
html, body {
  margin: 0;
  padding: 0;
  overflow: auto;
  background: transparent;
}

.cm-editor {
  height: 100vh;
  background: transparent;
  font-kerning: none;
}
```

- [ ] **Step 2: Rebuild the editor bundle**

Run: `cd ~/src/MarkEdit/CoreEditor && yarn build`
Expected: `✓ built`, `dist/index.html` regenerated.

- [ ] **Step 3: Add a translucent backdrop behind the web view**

In `EditorViewController.swift`, add near the other custom views (by `modernEffectView`, ~line 89):

```swift
// Full-bleed translucent backdrop so the desktop blurs through the editor.
let backdropView: MaterialView = {
  let view = MaterialView()
  view.blendingMode = .behindWindow
  view.material = .underWindowBackground
  view.state = .followsWindowActiveState
  view.translatesAutoresizingMaskIntoConstraints = false
  return view
}()
```

In the view-setup path where `webView` is added to the hierarchy, insert `backdropView` as the lowest subview, pinned to all edges of the content view, and honour reduce-transparency:

```swift
backdropView.isHidden = AppDesign.reduceTransparency
view.addSubview(backdropView, positioned: .below, relativeTo: nil)
NSLayoutConstraint.activate([
  backdropView.topAnchor.constraint(equalTo: view.topAnchor),
  backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
  backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
  backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
])
```

- [ ] **Step 4: Stop the web view painting its own background**

In `EditorViewController.swift`, in the `webView` lazy initializer after `let webView = EditorWebView(...)` (~line 184):

```swift
webView.setValue(false, forKey: "drawsBackground") // let the backdrop show through
```

- [ ] **Step 5: Make the window non-opaque when translucent**

In `EditorWindow.swift` `awakeFromNib()`, after the existing setup:

```swift
let translucent = !AppDesign.reduceTransparency
isOpaque = !translucent
backgroundColor = translucent ? .clear : backgroundColor
```

- [ ] **Step 6: Build and verify in-app**

Run: open `MarkEdit.xcodeproj`, ⌘R. Over a colourful desktop/window, confirm the editor shows a subtle blur and text stays crisp. Toggle Settings → reduce transparency (or System Settings → Accessibility → Reduce transparency) and confirm the window returns fully opaque.
Expected: blur visible when translucency on; opaque when reduced.

- [ ] **Step 7: Commit**

```bash
cd ~/src/MarkEdit
git add CoreEditor/index.css CoreEditor/dist/index.html MarkEditMac/Sources/Editor
git commit -m "feat: subtle window translucency across editor windows"
```

---

## Task 2: Markdown + UI typography

**Files:**
- Modify: `CoreEditor/index.css` (Markdown body rhythm, measure, heading scale)

**Interfaces:**
- Consumes: existing emitted classes from `CoreEditor/src/styling/markdown.ts` (`cm-md-header`, `cm-md-heading1…6`).
- Produces: no new symbols; visual-only.

- [ ] **Step 1: Add breathing-room typography rules**

Append to `CoreEditor/index.css` (values are the starting point; tune visually in Step 3). User font-size preference still applies via CodeMirror; these set rhythm and measure:

```css
/* Reading rhythm */
.cm-content {
  line-height: 1.65;
  padding-block: 12px;
  max-width: 78ch;
  margin-inline: auto;
  padding-inline: 24px;
}

/* Heading scale + vertical rhythm */
.cm-md-header { line-height: 1.3; }
.cm-line:has(.cm-md-heading1) { margin-top: 1.6em; margin-bottom: 0.4em; }
.cm-line:has(.cm-md-heading2) { margin-top: 1.4em; margin-bottom: 0.35em; }
.cm-line:has(.cm-md-heading3) { margin-top: 1.2em; margin-bottom: 0.3em; }
```

- [ ] **Step 2: Rebuild the bundle**

Run: `cd ~/src/MarkEdit/CoreEditor && yarn build`
Expected: `✓ built`.

- [ ] **Step 3: Build and verify in-app**

Run: Xcode ⌘R. Open a Markdown file with headings, paragraphs, and lists. Confirm: comfortable line spacing, a centered readable column (not edge-to-edge), and clear heading separation. Adjust the numbers in Step 1 to taste and re-run `yarn build`.
Expected: noticeably more breathing room without a theme/colour change.

- [ ] **Step 4: Commit**

```bash
cd ~/src/MarkEdit
git add CoreEditor/index.css CoreEditor/dist/index.html
git commit -m "feat: roomier Markdown typography defaults"
```

---

## Task 3: Right-edge overlay (Option+`)

Built in three sub-steps: a pure frame helper (unit-tested), the window overlay-mode + auto-hide, then the global hotkey wiring.

**Files:**
- Create: `MarkEditMac/Sources/Editor/EditorOverlayGeometry.swift` (pure frame math)
- Create: `MarkEditMac/Modules/Tests/EditorOverlayGeometryTests.swift`
- Modify: `MarkEditMac/Sources/Editor/EditorWindow.swift` (overlay mode enter/exit, resign-key auto-hide, Esc)
- Modify: `MarkEditMac/Sources/Main/Application/AppDelegate.swift` (register Option+` hotkey)
- Modify: `MarkEditMac/Sources/Main/Application/AppDelegate+Document.swift` (`toggleOverlay()`)

**Interfaces:**
- Produces:
  - `enum EditorOverlayGeometry { static func frame(in visibleFrame: NSRect, widthFraction: CGFloat) -> NSRect }`
  - `EditorWindow.overlayMode: Bool { get }`, `EditorWindow.enterOverlayMode(animated:)`, `EditorWindow.exitOverlayMode(animated:)`
  - `AppDelegate.toggleOverlay()`

- [ ] **Step 1: Write the failing frame-geometry test**

Create `MarkEditMac/Modules/Tests/EditorOverlayGeometryTests.swift`:

```swift
import XCTest
import AppKit
@testable import MarkEditMac

final class EditorOverlayGeometryTests: XCTestCase {
  func testFrameIsFlushToRightEdgeFullHeight() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = EditorOverlayGeometry.frame(in: visible, widthFraction: 1.0 / 3.0)
    XCTAssertEqual(frame.width, 480, accuracy: 0.5)   // 1440 / 3
    XCTAssertEqual(frame.height, 900, accuracy: 0.5)  // full visible height
    XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.5) // flush right
    XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.5)
  }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `xcodebuild test -project MarkEdit.xcodeproj -scheme MarkEdit -only-testing:MarkEditMacTests/EditorOverlayGeometryTests 2>&1 | tail -20`
Expected: FAIL — `EditorOverlayGeometry` is undefined.

- [ ] **Step 3: Implement the geometry helper**

Create `MarkEditMac/Sources/Editor/EditorOverlayGeometry.swift`:

```swift
import AppKit

/// Pure geometry for the right-edge overlay window. No side effects; unit-tested.
enum EditorOverlayGeometry {
  /// A rect flush to the right of `visibleFrame`, full height,
  /// `widthFraction` of the visible width.
  static func frame(in visibleFrame: NSRect, widthFraction: CGFloat) -> NSRect {
    let width = (visibleFrame.width * widthFraction).rounded()
    return NSRect(
      x: visibleFrame.maxX - width,
      y: visibleFrame.minY,
      width: width,
      height: visibleFrame.height
    )
  }

  /// Same size, parked just off the right screen edge (start of the slide-in).
  static func offscreenFrame(in visibleFrame: NSRect, widthFraction: CGFloat) -> NSRect {
    var frame = frame(in: visibleFrame, widthFraction: widthFraction)
    frame.origin.x = visibleFrame.maxX
    return frame
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `xcodebuild test -project MarkEdit.xcodeproj -scheme MarkEdit -only-testing:MarkEditMacTests/EditorOverlayGeometryTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Add overlay mode to EditorWindow**

In `EditorWindow.swift`, add state + enter/exit. Store the pre-overlay frame/level/behavior to restore later. Honour `reduceMotion`:

```swift
private(set) var overlayMode = false
private var savedFrame: NSRect?
private var savedLevel: NSWindow.Level?
private var savedCollectionBehavior: NSWindow.CollectionBehavior?
private let overlayWidthFraction: CGFloat = 1.0 / 3.0

func enterOverlayMode(animated: Bool) {
  guard !overlayMode, let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
  overlayMode = true
  savedFrame = frame
  savedLevel = level
  savedCollectionBehavior = collectionBehavior

  level = .floating
  collectionBehavior.insert(.canJoinAllSpaces)
  collectionBehavior.insert(.fullScreenAuxiliary)

  let target = EditorOverlayGeometry.frame(in: visible, widthFraction: overlayWidthFraction)
  if animated && !AppDesign.reduceMotion {
    setFrame(EditorOverlayGeometry.offscreenFrame(in: visible, widthFraction: overlayWidthFraction), display: false)
    makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { $0.duration = 0.18; animator().setFrame(target, display: true) }
  } else {
    setFrame(target, display: true)
    makeKeyAndOrderFront(nil)
  }
}

func exitOverlayMode(animated: Bool) {
  guard overlayMode else { return }
  overlayMode = false
  if let savedLevel { level = savedLevel }
  if let savedCollectionBehavior { collectionBehavior = savedCollectionBehavior }

  let restore = { [weak self] in
    if let savedFrame = self?.savedFrame { self?.setFrame(savedFrame, display: true) }
    self?.orderOut(nil)
  }
  if animated && !AppDesign.reduceMotion, let visible = (screen ?? NSScreen.main)?.visibleFrame {
    let off = EditorOverlayGeometry.offscreenFrame(in: visible, widthFraction: overlayWidthFraction)
    NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; animator().setFrame(off, display: true) },
                                         completionHandler: restore)
  } else {
    restore()
  }
}
```

- [ ] **Step 6: Auto-hide on focus loss and Esc**

In `EditorWindow.swift`, hide the overlay when another window/app takes key focus, and on Esc:

```swift
override func resignKey() {
  super.resignKey()
  if overlayMode { exitOverlayMode(animated: true) }
}

override func cancelOperation(_ sender: Any?) {
  if overlayMode { exitOverlayMode(animated: true) } else { super.cancelOperation(sender) }
}
```

- [ ] **Step 7: Add `toggleOverlay()` to the app delegate**

In `AppDelegate+Document.swift`, alongside `toggleDocumentWindowVisibility()`:

```swift
func toggleOverlay() {
  let editors = NSApp.windows.compactMap { $0 as? EditorWindow }

  // Already overlaying and focused → dismiss.
  if let overlaying = editors.first(where: { $0.overlayMode && $0.isKeyWindow }) {
    overlaying.exitOverlayMode(animated: true)
    NSApp.hide(nil)
    return
  }

  // No editor window → create one, then overlay once it exists.
  guard let target = editors.first(where: { $0.isKeyWindow }) ?? editors.first else {
    openOrCreateDocument(sender: NSApp)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      NSApp.activate(ignoringOtherApps: true)
      (NSApp.windows.compactMap { $0 as? EditorWindow }.first)?.enterOverlayMode(animated: true)
      _ = self
    }
    return
  }

  NSApp.activate(ignoringOtherApps: true)
  target.enterOverlayMode(animated: true)
}
```

- [ ] **Step 8: Register the Option+` global hotkey**

In `AppDelegate.swift`, right after the existing `mainWindowHotKey` registration block (~line 101):

```swift
// Personal fork: Option+` summons the editor as a right-edge overlay (Ghostty-style).
AppHotKeys.register(keyEquivalent: "~", modifiers: ["Option"]) {
  self.toggleOverlay()
}
```

- [ ] **Step 9: Build and verify end-to-end**

Run: Xcode ⌘R, then switch to another app (e.g. Safari). Press **Option+`**.
Expected: the editor slides in from the right edge, floating above the other app, showing the last document. Click into the other app → it slides away. Option+` again → returns. Press Esc while it's up → slides away. Confirm Ctrl+` still triggers Ghostty, not MarkEdit.

- [ ] **Step 10: Commit**

```bash
cd ~/src/MarkEdit
git add MarkEditMac/Sources/Editor/EditorOverlayGeometry.swift \
        MarkEditMac/Modules/Tests/EditorOverlayGeometryTests.swift \
        MarkEditMac/Sources/Editor/EditorWindow.swift \
        MarkEditMac/Sources/Main/Application/AppDelegate.swift \
        MarkEditMac/Sources/Main/Application/AppDelegate+Document.swift
git commit -m "feat: Option+backtick right-edge overlay (Ghostty-style summon)"
```

---

## Notes / risk register

- **`drawsBackground` KVC (Task 1 Step 4):** `setValue(false, forKey:)` on WKWebView is the long-standing way to get a transparent web view on macOS; if a future WebKit drops it, fall back to `underPageBackgroundColor = .clear` plus an `EditorWebView` `isOpaque` override.
- **`.cm-line:has(...)` (Task 2):** `:has()` is supported in the WebKit MarkEdit ships on (macOS 15+). If heading margins don't apply, move the rhythm onto the `.cm-md-heading*` inline spans instead.
- **Test scheme names (Task 3):** `-scheme MarkEdit` / `-only-testing:MarkEditMacTests/...` — confirm the exact scheme + test-target names in Xcode; adjust the `xcodebuild` invocation if they differ.
- **Full-screen source window (Task 3):** entering overlay from a full-screen editor is out of scope for v1 — `enterOverlayMode` assumes a normal windowed source. Guard/skip if `styleMask.contains(.fullScreen)`.
```
