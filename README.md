<p align="center">
  <img src="MarkEditMac/Resources/AppIcon.icon/Assets/Trace.png" width="96">
</p>

<h1 align="center">Trace</h1>

<p align="center"><em>A quiet place to write.</em></p>

Trace is a minimal Markdown writer for macOS, built for prose rather than code. It's a heavily reworked fork of the excellent [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) — same fast, native CodeMirror core, reshaped around one idea: **the words are the interface**.

Markdown without the markup. Syntax marks fade away as you write, the toolbar floats out of reach until you need it, and the page runs edge to edge under a soft glass surface.

## What it does

- **Concealed syntax** — `**`, `#`, `[]()` and friends disappear once written; your document reads like the finished piece. One toggle brings back the plumbing as a proper source mode: raw marks, line numbers on the bare canvas, and a live selection status.
- **Floating toolbar** — a small capsule at the bottom of the window with the handful of actions prose actually needs: table of contents, headings, bold, italic, lists, syntax visibility, and focus mode. It recedes while you type and returns when you reach for the mouse. Active states glow in your accent color.
- **Seamless glass window** — no title bar band, no toolbar chrome. The document bleeds to the window edge over a subtly blurred backdrop that stays alive even when the window is in the background, in light and dark.
- **Focus mode** — dims everything except the lines you're working on.
- **Typewriter scrolling** — the caret holds the vertical center of the screen; the text moves, you don't.
- **Overlay mode** — summon any document as a floating right-edge panel above your other apps, for notes alongside whatever you're doing.
- **A caret with a pulse** — glides between positions and breathes at rest instead of blinking. (Respects Reduce Motion.)
- **A welcome, not a blank stare** — launching without a document shows recent files and New/Open, then gets out of the way.
- **Two kinds of list** — bulleted (`*`, rendered as round bullets) and dashed (`-`, rendered literally), plus ordered and todo. Bullets and numbers take the accent color.
- **Accent colors** — Amber, Crimson, Fern, Teal, Azure, or Graphite; each tuned separately for light and dark so the caret, selection, bullets, and toolbar stay legible on both.
- **One theme, done well** — GitHub in light and dark, following the system or pinned to either. Three line heights, from tight to relaxed.

## What it doesn't do

Trace is deliberately smaller than MarkEdit. The updater, AppleScript and Shortcuts support, the extensions manager, the assistant pane, Pandoc export, and the classic toolbar were all removed. If you want the full-featured editor, use [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) — it's great.

## Under the hood

Everything that makes MarkEdit fast is still here:

- Native AppKit shell with a CodeMirror 6 core — a small app that opens instantly and handles very large documents without breaking a sweat.
- Real Markdown parsing (Lezer, following the GFM spec), not regex.
- Plain text files on disk. No library, no lock-in, no cloud, no data collection.

## Requirements & building

- macOS 15.0+ (the full glass treatment needs macOS 26 Tahoe; earlier versions fall back gracefully)
- Build with Xcode: open `MarkEdit.xcodeproj` and run the **MarkEditMac** scheme.
- The editor core lives in `CoreEditor/` (TypeScript). After changing it: `cd CoreEditor && yarn install && yarn build`, then rebuild the app.

## Credits

Trace is built on [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) by [cyanzhong](https://github.com/cyanzhong) and contributors, released under the MIT license, with [CodeMirror 6](https://codemirror.net/) at its core and [ts-gyb](https://github.com/microsoft/ts-gyb) for code generation. The heart of this app is their work — this fork just gives it a quieter voice.
