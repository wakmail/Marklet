import Foundation

/// Source ranges use UTF16 offsets, matching NSString and AppKit.
public enum Markdown {
    public struct Emphasis: Equatable, Sendable {
        public enum Kind: Sendable { case italic, bold }
        public let kind: Kind
        public let openingMarker: NSRange
        public let closingMarker: NSRange
        public let content: NSRange
        public let range: NSRange
    }

    public struct CodeBlock: Equatable, Sendable {
        public let range: NSRange
        public let openingFence: NSRange
        public let closingFence: NSRange?
        public let content: NSRange
        public let info: String
        public let quoteDepth: Int
    }

    public static func emphasis(in source: String) -> [Emphasis] {
        MarkdownParser.emphasis(in: source).map {
            Emphasis(kind: $0.kind == .strong ? .bold : .italic,
                     openingMarker: $0.openingMarkerRange, closingMarker: $0.closingMarkerRange,
                     content: $0.contentRange, range: $0.fullRange)
        }
    }

    public static func codeBlocks(in source: String) -> [CodeBlock] {
        MarkdownParser.codeBlocks(in: source).map {
            CodeBlock(range: $0.range, openingFence: $0.openingFenceRange,
                      closingFence: $0.closingFenceRange, content: $0.interiorRange,
                      info: $0.infoString, quoteDepth: $0.blockquoteDepth)
        }
    }

    public static func inlineCodeRanges(in source: String) -> [NSRange] {
        MarkdownParser.inlineCodeSpans(in: source).map(\.range)
    }

    public static func inlineMathRanges(in source: String) -> [NSRange] {
        MarkdownParser.inlineMathRanges(in: source)
    }

    public static func blockMathRanges(in source: String) -> [NSRange] {
        MarkdownParser.blockMathRanges(in: source)
    }

    public static func tableRanges(in source: String) -> [NSRange] {
        MarkdownParser.tableBlockRanges(in: source)
    }

    public static func frontMatterRange(in source: String) -> NSRange? {
        MarkdownParser.frontMatter(in: source)?.range
    }
}
