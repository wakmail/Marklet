# Native core demo

Run from the repository root on macOS:

```sh
swift run --package-path Examples/CoreDemo CoreDemo
```

Edit Markdown on the left to update native attributed text on the right.
Choose System, Warm, or Dark to try different text palettes. These are demo
palettes, not the Marklet app theme library.

Generate the README image from the same AppKit view:

```sh
swift run --package-path Examples/CoreDemo CoreDemo --snapshot media/core-demo.png
```

Snapshot output uses only synthetic sample text. The PNG writer retains only
pixel data and required image structure, removing ancillary metadata such as
text, author, timestamps, EXIF, and color profiles. Review visible content before
publishing screenshots made with modified samples.
