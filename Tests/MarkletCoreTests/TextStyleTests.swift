import AppKit
import Testing
import MarkletCore

@MainActor
struct TextStyleTests {
    @Test func suppliedFontsAndColors() throws {
        var style = MarkdownTextStyle()
        style.bodyFont = .monospacedSystemFont(ofSize: 20, weight: .regular)
        style.bodyColor = .brown
        style.headingColor = .orange
        style.boldColor = .red
        style.italicColor = .green
        style.boldItalicColor = .purple
        style.codeColor = .cyan
        style.codeFont = .monospacedSystemFont(ofSize: 18, weight: .medium)
        style.codeBackgroundColor = nil
        style.linkColor = .blue
        let text = try MarkdownTextRenderer(style: style).render(
            "# Heading\n\nBody **bold** *italic* ***both*** `code` [link](https://example.com)"
        )
        func attribute(_ key: NSAttributedString.Key, _ word: String) -> Any? {
            text.attribute(key, at: (text.string as NSString).range(of: word).location, effectiveRange: nil)
        }
        for (word, color) in [("Heading", NSColor.orange), ("Body", .brown), ("bold", .red),
                              ("italic", .green), ("both", .purple), ("code", .cyan), ("link", .blue)] {
            #expect((attribute(.foregroundColor, word) as? NSColor) == color)
        }
        #expect((attribute(.font, "Heading") as? NSFont)?.pointSize == 40)
        #expect((attribute(.font, "Heading") as? NSFont)?.familyName == style.bodyFont.familyName)
        #expect((attribute(.font, "Body") as? NSFont) == style.bodyFont)
        #expect((attribute(.font, "code") as? NSFont) == style.codeFont)
        #expect(attribute(.backgroundColor, "code") == nil)
        #expect((attribute(.link, "link") as? URL)?.absoluteString == "https://example.com")
    }

    @Test func defaultsFollowBodyStyleWithoutLeakingBetweenRenderers() throws {
        var style = MarkdownTextStyle()
        style.bodyFont = .systemFont(ofSize: 23)
        style.bodyColor = .magenta
        let custom = try MarkdownTextRenderer(style: style).render("***both*** `code`")
        #expect((custom.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .magenta)
        let index = (custom.string as NSString).range(of: "code").location
        #expect((custom.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize == 23)
        let standard = try MarkdownTextRenderer().render("Body")
        #expect((standard.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 16)
        #expect((standard.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .labelColor)
    }
}
