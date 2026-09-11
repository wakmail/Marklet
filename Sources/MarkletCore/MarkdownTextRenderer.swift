import AppKit

@MainActor
public struct MarkdownTextRenderer {
    public init() {}

    /// Returns display text, with Markdown syntax removed. Output ranges differ from source ranges.
    public func render(_ markdown: String) throws -> NSAttributedString {
        let parsed = try AttributedString(markdown: markdown)
        let result = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        for run in parsed.runs {
            let block = run.presentationIntent?.components.first
            if let identity = block?.identity, let previousBlock, identity != previousBlock {
                result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            }
            if let identity = block?.identity { previousBlock = identity }
            var attributes = bodyAttributes
            var font = NSFont.systemFont(ofSize: 16)
            var codeBlock = false
            if let components = run.presentationIntent?.components {
                for component in components {
                    if case .codeBlock = component.kind { codeBlock = true }
                    if case .header(let level) = component.kind {
                        let scale = [2.0, 1.6, 1.35, 1.2, 1.1, 1.0][min(5, max(0, level - 1))]
                        font = NSFont.boldSystemFont(ofSize: 16 * scale)
                    }
                }
            }
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            if codeBlock || intent.contains(.code) {
                font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor
            }
            attributes[.font] = font
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return NSAttributedString(attributedString: result)
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        return [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph]
    }
}
