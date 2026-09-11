import AppKit

@MainActor
public struct MarkdownTextStyle {
    public var bodyFont: NSFont = .systemFont(ofSize: 16)
    public var codeFont: NSFont?
    public var bodyColor: NSColor = .labelColor
    public var headingColor: NSColor?
    public var boldColor: NSColor?
    public var italicColor: NSColor?
    public var boldItalicColor: NSColor?
    public var codeColor: NSColor?
    public var codeBackgroundColor: NSColor? = .quaternaryLabelColor
    public var linkColor: NSColor = .linkColor

    public init() {}
}
