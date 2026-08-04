<p align="center">
  <img src="MarkEditMac/Resources/AppIcon.icon/Assets/Trace.png" width="96">
</p>

<h1 align="center">Trace</h1>

<p align="center"><em>A quiet place to write.</em></p>

Trace is a minimal Markdown writer for macOS, built for prose rather than code. It's a heavily reworked fork of the excellent [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) — same fast, native CodeMirror core, reshaped around one idea: **the words are the interface**.

Markdown without the markup. Syntax marks fade away as you write, the toolbar floats out of reach until you need it, and the page runs edge to edge under a soft glass surface.

## What it does

- **Concealed syntax** — `**`, `#`, `[]()` and friends disappear once written; your document reads like the finished piece. Toggle them back from the floating toolbar when you need to see the plumbing.
- **Floating toolbar** — a small capsule at the bottom of the window with the handful of actions prose actually needs: table of contents, headings, bold, italic, lists, syntax visibility, and focus mode. It recedes while you type and returns when you reach for the mouse. Active states glow amber.
- **Seamless glass window** — no title bar band, no toolbar chrome. The document bleeds to the window edge over a subtly blurred backdrop, in light and dark.
- **Focus mode** — dims everything except the lines you're working on.
- **Overlay mode** — summon any document as a floating right-edge panel above your other apps, for notes alongside whatever you're doing.
- **A caret with a pulse** — glides between positions and breathes at rest instead of blinking. (Respects Reduce Motion.)
- **Four themes** — GitHub and Minimal, in light and dark pairs, unified by a warm amber accent.

## What it doesn't do

Trace is deliberately smaller than MarkEdit. The updater, AppleScript and Shortcuts support, the extensions manager, the assistant pane, Pandoc export, and the classic toolbar were all removed. If you want the full-featured editor, use [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) — it's great.

## Under the hood

Everything that makes MarkEdit fast is still here:

- Native AppKit shell with a CodeMirror 6 core — a small app that opens instantly and handles very large documents without breaking a sweat.
- Real Markdown parsing (Lezer, following the GFM spec), not regex.
- Plain text files on disk. No library, no lock-in, no cloud, no data collection.

## Requirements & building

- macOS 15.0+
- Build with Xcode: open `MarkEdit.xcodeproj` and run the **MarkEditMac** scheme.
- The editor core lives in `CoreEditor/` (TypeScript). After changing it: `cd CoreEditor && yarn install && yarn build`, then rebuild the app.

## Credits

Trace is built on [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) by [cyanzhong](https://github.com/cyanzhong) and contributors, released under the MIT license, with [CodeMirror 6](https://codemirror.net/) at its core and [ts-gyb](https://github.com/microsoft/ts-gyb) for code generation. The heart of this app is their work — this fork just gives it a quieter voice.
