# Marklet Core

The Markdown parsing core used by Marklet, packaged as a Swift library.

This package provides source ranges for emphasis, fenced code, inline code,
math, tables, and front matter, plus basic native text rendering. It has no external
package dependencies.
It does not include the Marklet application, editor behavior, window styling, theme
importing, or licensing system.
It is a source analysis library, not a complete Markdown to HTML converter.
The API is experimental.

Requires Swift 6.1 and macOS 14 or later. Other platforms have not been tested.

```swift
import Foundation
import MarkletCore

let source = "Hello **world**"
for span in Markdown.emphasis(in: source) {
    print((source as NSString).substring(with: span.content))
}
```

Ranges use UTF16 offsets. Nested emphasis content can contain the inner syntax
markers. Keep the original source when using these ranges.

Run `swift test` to build the library and exercise its public API.

## Native text rendering

`MarkdownTextRenderer` returns an `NSAttributedString` for use in AppKit. It supports
headings, paragraphs, combined bold and italic, inline and block code, and link attributes.
It uses Foundation Markdown parsing and AppKit font attributes. No HTML or web view is used.
This basic renderer does not reproduce the complete Marklet editor or its extended syntax.
Table layout, list markers, images, callouts, and rendered equations are outside its scope.

```swift
import AppKit
import MarkletCore

@MainActor
func showNote(in textView: NSTextView) throws {
    var style = MarkdownTextStyle()
    style.bodyFont = .systemFont(ofSize: 18)
    style.headingColor = .systemPurple
    style.boldItalicColor = .systemPink
    style.linkColor = .systemBlue

    let renderer = MarkdownTextRenderer(style: style)
    let text = try renderer.render("# Welcome\n\nA ***small*** note with `code`.")
    textView.textStorage?.setAttributedString(text)
}
```

Rendering must run on the main actor. Markdown markers are removed, so rendered
positions must not be used as source offsets. Unlike the source range parser, this
renderer follows Foundation Markdown behavior. It does not promise preservation of
source whitespace or editor round trips.

Colors default to native dynamic system colors. Optional heading and emphasis colors
inherit the surrounding text color when unset. Combined emphasis uses its explicit
color, then bold, then italic, then the surrounding color. Code inherits body color
and size unless overridden; set `codeBackgroundColor` to `nil` to omit its fill.
Native text views can apply their own `linkTextAttributes`; configure those on the host
view if it overrides your supplied link color.

## License and provenance

The existing GPLv3 license and additional permission are preserved in LICENSE
and LICENSE.additional-terms. PROVENANCE.json records the source revision and
SHA256 hashes of the source inputs and exported files. Exported comments may differ
from the internal source; parser behavior is unchanged.
