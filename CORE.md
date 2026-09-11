# Marklet Core

The Markdown parsing core used by Marklet, packaged as a Swift library.

This initial export provides source ranges for emphasis, fenced code, inline code,
math, tables, and front matter. It has no external package dependencies.
It does not include the Marklet application, editor, rendering, themes, or licensing system.
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

## License and provenance

The existing GPLv3 license and additional permission are preserved in LICENSE
and LICENSE.additional-terms. PROVENANCE.json records the source revision and
SHA256 hashes of the source inputs and exported files. Exported comments may differ
from the internal source; parser behavior is unchanged.
