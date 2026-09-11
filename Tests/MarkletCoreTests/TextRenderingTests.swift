import AppKit
import Testing
import MarkletCore

@MainActor
struct TextRenderingTests {
    private func font(_ text: NSAttributedString, _ word: String) -> NSFont {
        text.attribute(.font, at: (text.string as NSString).range(of: word).location,
                       effectiveRange: nil) as! NSFont
    }

    @Test func headingsAndParagraphs() throws {
        let result = try MarkdownTextRenderer().render("# Title\n\nBody\n\n## Second")
        #expect(result.string == "Title\nBody\nSecond")
        #expect(font(result, "Title").pointSize > font(result, "Second").pointSize)
        #expect(font(result, "Second").pointSize > font(result, "Body").pointSize)
    }

    @Test func composedEmphasis() throws {
        let result = try MarkdownTextRenderer().render("Plain **bold** *italic* ***both*** plain")
        #expect(result.string == "Plain bold italic both plain")
        let manager = NSFontManager.shared
        #expect(manager.traits(of: font(result, "bold")).contains(.boldFontMask))
        #expect(manager.traits(of: font(result, "italic")).contains(.italicFontMask))
        let combined = manager.traits(of: font(result, "both"))
        #expect(combined.contains(.boldFontMask) && combined.contains(.italicFontMask))
        #expect(!manager.traits(of: font(result, "Plain")).contains(.boldFontMask))
    }

    @Test func unicodeEscapesAndEmptyInput() throws {
        let renderer = MarkdownTextRenderer()
        #expect(try renderer.render("").length == 0)
        let text = try renderer.render(#"🪴 \*literal\* **café**"#)
        #expect(text.string == "🪴 *literal* café")
        #expect(NSFontManager.shared.traits(of: font(text, "café")).contains(.boldFontMask))
    }
}
