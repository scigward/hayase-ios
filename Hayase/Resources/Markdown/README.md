# Markdown editor runtime

Production resources used by `MarkdownEditorView` (`Components/UI/Forums/Write.swift`), the editor of the reply writer. All code is bundled; nothing is fetched at build or run time.

Reference: the interface's `src/lib/components/ui/markdown/markdown.svelte` and its `overtype` 2.4.0 package.

- overtype.min.js: OverType 2.4.0, npm package `dist/overtype.min.js` (MIT; overtype-LICENSE.txt).
- editor.html: the page of the editor. It mounts OverType with the options and the theme of `markdown.svelte` (toolbar, `autoResize: false`, the custom colours, the placeholder) inside a box that is `border border-input flex overflow-clip`, and posts the text to the app on every change (`change`) or on request (`HayaseEditor.value()`).

Update the library together with the interface reference: the toolbar, the shortcuts, the syntax colouring and the list handling are the library's own, which is why a native text view is not used.
