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

## Make it yours

Write with live formatting, edit tables in place, and choose a theme that feels right.

[![Marklet in Nord showing a weekly plan with an editable table and checklist](media/screenshots/02-nord-tables.png)](media/screenshots/02-nord-tables.png)

*Nord, with two editing mode controls and the floating formatting toolbar.*

<table>
  <tr>
    <td><a href="media/screenshots/03-catppuccin-light.png"><img src="media/screenshots/03-catppuccin-light.png" alt="Marklet in Catppuccin Latte with formatted notes and a highlighted sentence" width="460"></a></td>
    <td><a href="media/screenshots/05-dracula-code.png"><img src="media/screenshots/05-dracula-code.png" alt="Marklet in Dracula with a syntax highlighted Swift code block" width="460"></a></td>
  </tr>
  <tr>
    <td align="center">Catppuccin Latte</td>
    <td align="center">Dracula</td>
  </tr>
</table>

Find [Nord](https://github.com/insanum/obsidian_nord), [Catppuccin](https://github.com/catppuccin/obsidian), and [Dracula](https://github.com/dracula/obsidian) in Marklet's community theme browser. Preview their supported colors before choosing a theme.

[More screenshots: Marklet Warm, Catppuccin Mocha math, and Paper reading](SCREENSHOTS.md)

## Quick thoughts with Scraps

Keep a floating notepad close by for ideas, reminders, and small checklists. Enable Scraps in Settings when you want it. Your notes stay in Markdown files.

<a href="media/screenshots/08-scraps-panel.png"><img src="media/screenshots/08-scraps-panel.png" alt="The standalone Scraps panel in Nord with a short note and checklist" width="520"></a>

These screenshots show the full Marklet app. The standalone open source core demo is below.

## Open source core

Marklet’s Markdown parsing core is open source under GPLv3 with the additional
permission in [LICENSE.additional-terms](LICENSE.additional-terms). The full app
and its editor remain in a private repository.

The core is a standalone Swift package with no external package dependencies.
It exposes source ranges for emphasis, code, math, tables, and front matter, plus
basic native text rendering with configurable fonts and colors.
See [CORE.md](CORE.md) for usage, scope, and attribution.

![Native core demo showing Markdown source and styled text](media/core-demo.png)

Try the [native demo](Examples/CoreDemo): edit Markdown and switch text palettes.

Requires Swift 6.1 and macOS 14 or later. Run `swift test` to build and test the core.


<div align="center">
  
[getmarklet.com](https://getmarklet.com)

</div>
