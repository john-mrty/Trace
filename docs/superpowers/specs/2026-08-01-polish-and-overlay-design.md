# MarkEdit personal fork — visual polish + right-edge overlay

**Date:** 2026-08-01
**Author:** John Moriarty
**Status:** Approved design, ready for implementation planning

## Goal

Refine MarkEdit's look and feel and add a Ghostty-style quick-summon overlay, as a personal fork. Three independent workstreams:

- **A. Translucency** — subtle blurred, semi-transparent window backgrounds across all windows.
- **B. Typography** — tighter UI chrome type; more breathing room and better defaults for the Markdown viewer.
- **C. Right-edge overlay** — a global hotkey that slides the editor in from the right edge as a floating, auto-hiding companion over other apps.

These can be built and shipped independently; A and B are low-risk CSS/material tuning, C is the one genuinely new piece.

## Context / existing foundations

Grounded against the cloned source (`~/src/MarkEdit`):

- **Global hotkey infra exists.** `AppHotKeys` (`MarkEditMac/Sources/Main/AppHotKeys.swift`) registers true system-wide hotkeys via Carbon `RegisterEventHotKey` (fires when the app is unfocused). There is already one caller: `AppDelegate.swift:97` registers `AppRuntimeConfig.mainWindowHotKey` → `toggleDocumentWindowVisibility()` (`AppDelegate+Document.swift:78`), which summons/hides the last editor window and creates an untitled one when none exist.
- **Material/translucency abstraction exists.** `AppDesign.modernEffectView` (`MarkEditMac/Sources/Main/AppDesign.swift`) returns `NSGlassEffectView` (macOS 26) or `NSVisualEffectView`. `MaterialView` is used in `EditorViewController.swift:90`. A `reduceTransparency` preference already exists (`AppPreferences.Window.reduceTransparency`, plus the system accessibility flag).
- **Editor is a WKWebView** rendering CodeMirror 6 from `CoreEditor` (single-file bundle `CoreEditor/dist/index.html`). Markdown element classes are emitted in `CoreEditor/src/styling/markdown.ts` (`cm-md-heading1…6`, `cm-md-bold`, etc.); base CSS in `CoreEditor/index.css`. Colour themes live in `CoreEditor/src/styling/themes/` and stay untouched.

## A. Translucency (all windows)

- **Reuse:** `MaterialView` + `AppDesign.modernEffectView`, gated by the existing `reduceTransparency` pref.
- **Change:** set the editor window's material to `blendingMode = .behindWindow` with a subtle vibrancy material so the desktop blurs through.
- **The crux:** the `WKWebView` paints an opaque background today. Translucency is invisible until the web layer is transparent — set `drawsBackground = false` on the web view **and** make `body` / `.cm-editor` background transparent in `CoreEditor/index.css`. The colour theme then renders *over* the translucent material.
- **Tuning:** keep it subtle (~85–90% effective opacity, not fully glassy) for legibility over busy desktops. Honour `reduceTransparency` (and the system accessibility flag) — fall back to opaque when set.
- **Scope:** all windows (main editor + overlay share the same material path).

## B. Typography

- **Markdown breathing room** (`CoreEditor/index.css`, targeting existing `cm-md-*` classes):
  - line-height ~1.65 on body text (`.cm-content` / `.cm-line`).
  - generous paragraph spacing.
  - a clear heading scale with top/bottom margins on `.cm-md-heading1…6`.
  - a max line-measure + horizontal padding so text isn't edge-to-edge.
  - optional nicer default reading-font fallback stack (user font preference still wins).
- **Tighter UI chrome:** reduce toolbar / title-bar type sizing slightly for a more refined frame.
- Colour themes are not modified.

## C. Right-edge overlay (Option+`)

Chosen behavior (from brainstorming):
- **Content:** resumes the last document. No open document → new untitled buffer.
- **Dismiss:** auto-hide on focus loss (`resignKey`), plus Option+` toggle and Esc.
- **Placement:** slides in from the right screen edge as a tall side companion.

Implementation:
- **Hotkey:** register a second global hotkey **Option+`** (modifier `Option`, key `~` → keycode `0x32`) → new `toggleOverlay()`. Distinct from Ghostty's Ctrl+` (deliberately avoided) and from the existing `mainWindowHotKey`.
- **Presentation (approach C1, chosen):** reuse the existing frontmost/last-key `EditorWindow` and toggle an `overlayMode` that swaps window state:
  - frame pinned flush to the right screen edge, full height, ~1/3 screen width.
  - `level = .floating`.
  - `collectionBehavior` includes `.canJoinAllSpaces` + `.fullScreenAuxiliary` so it floats over whatever app is active, on the current Space.
  - slide-in-from-right animation; **respects `AppDesign.reduceMotion`** (no animation when set).
  - observe `resignKey` / window-did-resign to slide out and restore.
  - restore normal window state (level, frame, collectionBehavior) when the window is summoned the ordinary way or overlay mode is toggled off.
- **Rationale for C1 over a dedicated `NSPanel` (C2):** C1 avoids duplicating the document↔WebView plumbing and the risk of two views contending for one `NSDocument`. The overlay *is* the document window, repositioned — which is exactly what "resume last document" means. C2 (a separate panel hosting a second editor view) is cleaner in separation but more work and more bug surface; rejected for v1.

### C edge cases / open items
- Multiple editor windows/tabs open: v1 operates on the frontmost/last-key `EditorWindow` only.
- Entering overlay mode from a full-screen editor window: treat as normal-mode summon (don't force overlay) or exit full screen first — resolve during implementation.
- Persisting/restoring the exact pre-overlay frame so a normal summon returns the window where the user left it.

## Non-goals (YAGNI)

- No pin-to-stay control (dismiss is auto-hide only).
- No new colour themes or theme-system changes.
- No settings UI for overlay geometry in v1 (sensible fixed defaults; revisit if needed).
- No changes to document model, tabs, or file handling beyond what the overlay summon needs.

## Success criteria

- All editor windows show a subtle desktop blur; text stays legible; `reduceTransparency` returns fully opaque.
- Markdown viewer reads with noticeably more breathing room (spacing, measure, heading rhythm) without a theme change.
- Option+` from any app slides the editor in from the right with the last document; clicking away or Esc slides it out; Ctrl+` is untouched (Ghostty).
- Both editor bundle (`yarn build`) and the macOS app (Xcode ⌘R) build clean.
