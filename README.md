# MD View

Small macOS Markdown reader built with Swift and AppKit. Open a file with **⌘O**,
drop it into the window, or use Finder’s **Open With**. Save in your editor to
refresh automatically. **⌘F** finds text; **⌘R** reloads; **⌘+ / ⌘− / ⌘0** resize text.
**⌘ + mouse wheel up/down** increases/decreases text size, independent of natural scrolling.
All commands are in the macOS menus; the window contains only the document.

**Go → Back / Forward** navigates document links and heading anchors, restoring
scroll positions. Supports mouse side buttons, **⌘[ / ⌘]**, **⌘← / ⌘→**,
**⌥← / ⌥→**, **Delete / ⇧Delete**, swipe gestures, and media previous/next or
rewind/fast-forward events delivered to MD View. System trackpad swipe preferences
are respected. Keys reserved by macOS or a music player must be remapped to a
navigation shortcut. History keeps at most 128 locations, without caching documents.

Supports headings and anchors, emphasis, lists, task lists, quotes, tables, code,
links, local images, and fenced `mermaid` diagrams. Everything renders offline.
Raw HTML is displayed literally. Remote images remain as alt text; external
links open in your browser only when clicked. Local images must be inside the
document’s folder or its subfolders.

Language-labeled code fences have native, theme-aware syntax highlighting for
Swift, Python, JavaScript/TypeScript, Rust, C/C++, Java, C#, Go, Ruby, shell, SQL,
JSON, YAML/TOML/INI, HTML/XML, CSS, and diffs (common aliases supported).
Highlighting is lexical; embedded languages and interpolation are not parsed.
Unknown/unlabeled languages and blocks over 200,000 UTF-16 units stay plain.
See `examples/highlighting.md`. Code text and whitespace are preserved for copying.
Code blocks use [Catppuccin](https://github.com/catppuccin/palette): Mocha in dark
mode and Latte in light mode, switching automatically with the window’s appearance.

Mermaid follows the same appearance and the surrounding background. Click a
diagram for a modal overlay with a sharp vector preview. Use **⌘ + wheel**, pinch,
**⌘+ / ⌘−**, or the buttons to zoom; drag to pan. **⌘9** fits the diagram,
**⌘0** shows actual size. **Esc**, **⌘W**, right-click, Close, or clicking outside dismisses it.
Initial zoom and Fit keep diagram labels at least as large as the current document
text. Large diagrams may need panning rather than shrinking their text to fit.

## Build and run

Requires macOS 14.5+ and Swift 6.2+ (Xcode or Command Line Tools).

```sh
./build_app.sh
open "dist/MD View.app"
```

Install the latest build into `/Applications` and register it with macOS:

```sh
./install.sh
open -a "MD View"
```

Use `./install.sh --user` for `~/Applications`, or pass another Applications directory.
`--no-build` installs the existing bundle. Updates replace the previous installation;
quit and reopen an already-running app. The installer does not launch it or change
the default Markdown handler. The app is ad-hoc signed for local use.
The included Mermaid bundle means Node/npm are **not required to build or run**.
The app icon is generated from `Resources/AppIcon.svg` using native macOS tools
during the build. Regenerate it separately with `swift scripts/build_icon.swift`;
PNG sizes and the ICNS file stay in `.build/`.
To regenerate that bundle, install Node 22.12+ and run:

```sh
npm ci
npm run bundle
node scripts/notices.mjs
./build_app.sh
```

Run the native tests and offscreen integration checks with `./test.sh` (requires
Python 3 in addition to the build tools). No ripgrep installation is needed.
They never activate windows, switch workspaces, or send input. Generate a native
preview without desktop interaction:

```sh
"dist/MD View.app/Contents/MacOS/MDView" --preview "$PWD/examples/demo.md" "$PWD/.build/preview.png"
```

Append an optional width in points (400–3000) to check narrow or wide layouts.
Set `MDVIEW_PREVIEW_APPEARANCE=light` or `dark` to check either theme offscreen.
Set `MDVIEW_PREVIEW_DIAGRAM=0` to preview the first Mermaid diagram’s overlay.

## Resource use

The reader uses `NSTextView` and [Swift Markdown](https://github.com/swiftlang/swift-markdown)
(cmark). Its executable does not link WebKit or JavaScriptCore. Only documents
with Mermaid start a separate helper using the bundled [Mermaid](https://mermaid.js.org/)
library. It captures thumbnails and vector previews sequentially and exits; text-size changes
reuse those images. View → Render Mermaid Diagrams disables the helper entirely.
File system notifications drive reloads; there are no polling loops or servers.

Measured offscreen on this Apple Silicon Mac, macOS 26.7.1: **18 MiB physical
footprint** for a small plain document, **55 MiB** for the demo with two diagrams
(RSS: 84 / 150 MiB, including shared mappings). Values vary by document and OS.
Mermaid temporarily adds WebKit’s memory cost during rendering. The integration
check reports current measurements and verifies that the helper exits.

Bounds: one document/window, 4 MiB UTF-8 source, 32 rendered diagrams, 8 million
diagram pixels, 1400 pixels per diagram edge, 90-second helper timeout. Additional
diagram fences remain code; diagram errors show the source and an error message.
Local images are thumbnailed with a separate pixel budget. Browser-only diagram
interactions are unavailable; the native overlay supports zooming and panning.

Dependencies are pinned in `Package.resolved` and `package-lock.json`; license
texts ship in `Resources/THIRD-PARTY-NOTICES.txt`.

## License

MD View's code and documentation are available under the [MIT license](LICENSE).
Third-party components retain their own licenses; see
[notices](Resources/THIRD-PARTY-NOTICES.txt) and
[source availability](Resources/THIRD-PARTY-SOURCES.txt), including EPL-2.0 elkjs.
