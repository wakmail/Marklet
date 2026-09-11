<div align="center">

# Marklet

A lightweight native macOS Markdown editor.

[![Latest Release](https://img.shields.io/github/v/release/wakmail/Marklet?label=release&color=blue)](https://github.com/wakmail/Marklet/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/wakmail/Marklet/total?label=downloads&color=brightgreen)](https://github.com/wakmail/Marklet/releases)
[![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon%20%26%20Intel-black?logo=apple&logoColor=white)](https://apps.apple.com/app/id6791297358)
[![License](https://img.shields.io/github/license/wakmail/Marklet?color=brightgreen)](LICENSE)

</div>

Downloads and the open source parsing core for **Marklet**.

- Grab the latest version from the [Releases page](https://github.com/wakmail/Marklet/releases/latest).
- The direct download version checks for updates through Sparkle.

## Open source core

Marklet’s Markdown parsing core is open source under GPLv3 with the additional
permission in [LICENSE.additional-terms](LICENSE.additional-terms). The full app
and its editor remain in a private repository.

The core is a standalone Swift package with no external package dependencies.
It exposes source ranges for emphasis, code, math, tables, and front matter.
See [CORE.md](CORE.md) for usage, scope, and attribution.

Requires Swift 6.1 and macOS 14 or later. Run `swift test` to build and test the core.


<div align="center">
  
[getmarklet.com](https://getmarklet.com)

</div>
