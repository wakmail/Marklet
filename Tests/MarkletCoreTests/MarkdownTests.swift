import Foundation
import Testing
import MarkletCore

@Test func nestedEmphasis() {
    let result = Markdown.emphasis(in: "***hello***")
    #expect(result.count == 2)
    #expect(result.first { $0.kind == .bold }?.content == NSRange(location: 3, length: 5))
    #expect(result.first { $0.kind == .italic }?.content == NSRange(location: 1, length: 9))
    #expect(result.contains { $0.kind == .bold })
    #expect(result.contains { $0.kind == .italic })
}

@Test func protectedCodeAndEscapes() {
    #expect(Markdown.emphasis(in: #"`**code**` \*literal\*"#).isEmpty)
    #expect(Markdown.emphasis(in: "```\n**code**\n```\n").isEmpty)
}

@Test func unicodeRanges() {
    let source = "🪴 **café**" as NSString
    let result = Markdown.emphasis(in: source as String)
    #expect(result.count == 1)
    #expect(result.first?.content == source.range(of: "café"))
}

@Test func incompleteFence() {
    let result = Markdown.codeBlocks(in: "```swift\nlet x = 1\n")
    #expect(result.count == 1)
    #expect(result.first?.closingFence == nil)
    #expect(result.first?.info == "swift")
}

@Test func tablesAndFrontMatter() {
    #expect(Markdown.tableRanges(in: "| a | b |\n| --- | --- |\n| c | d |\n").count == 1)
    #expect(Markdown.frontMatterRange(in: "---\ntitle: hello\n---\nbody") != nil)
}

@Test func mathAndCurrency() {
    #expect(Markdown.inlineMathRanges(in: "Price $5 and $10").isEmpty)
    #expect(Markdown.inlineMathRanges(in: "$x^2$").count == 1)
    #expect(Markdown.blockMathRanges(in: "$$x^2$$").count == 1)
}
