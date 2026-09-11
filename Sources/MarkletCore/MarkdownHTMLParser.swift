import Foundation

enum MarkdownHTMLBlockType: Int, Equatable {
    case literalContainer = 1
    case comment = 2
    case processingInstruction = 3
    case declaration = 4
    case cdata = 5
    case blockTag = 6
    case completeTag = 7
}

enum MarkdownHTMLSpanKind: Equatable {
    case openTag
    case closingTag
    case comment
    case processingInstruction
    case declaration
    case cdata
}

struct MarkdownHTMLBlock: Equatable {
    let range: NSRange
    let contentRanges: [NSRange]
    let type: MarkdownHTMLBlockType
    let tagName: String?
    let isDisallowed: Bool
}

struct MarkdownHTMLSpan: Equatable {
    let range: NSRange
    let kind: MarkdownHTMLSpanKind
    let tagName: String?
    let isDisallowed: Bool
}

enum MarkdownInlineHTMLTag: String, CaseIterable, Equatable {
    case lineBreak = "br"
    case keyboard = "kbd"
    case subscriptText = "sub"
    case superscriptText = "sup"
    case bold = "b"
    case italic = "i"
    case code = "code"
}

struct MarkdownInlineHTMLElement: Equatable {
    let tag: MarkdownInlineHTMLTag
    let range: NSRange
    let openingTagRange: NSRange
    let contentRange: NSRange
    let closingTagRange: NSRange?
}

struct MarkdownCodeSpan: Equatable {
    let range: NSRange
    let openingDelimiterRange: NSRange
    let contentRange: NSRange
    let closingDelimiterRange: NSRange
}

struct MarkdownInlineTokens {
    let codeSpans: [MarkdownCodeSpan]
    let htmlSpans: [MarkdownHTMLSpan]
    let safeHTMLElements: [MarkdownInlineHTMLElement]
}

extension MarkdownParser {
    static let disallowedRawHTMLTags: Set<String> = [
        "title", "textarea", "style", "xmp", "iframe", "noembed",
        "noframes", "script", "plaintext"
    ]

    private static let htmlBlockTagNames: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote",
        "body", "caption", "center", "col", "colgroup", "dd", "details",
        "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2",
        "h3", "h4", "h5", "h6", "head", "header", "hr", "html",
        "iframe", "legend", "li", "link", "main", "menu", "menuitem",
        "nav", "noframes", "ol", "optgroup", "option", "p", "param",
        "search", "section", "summary", "table", "tbody", "td", "tfoot",
        "th", "thead", "title", "tr", "track", "ul"
    ]

    private static let literalHTMLBlockTagNames: Set<String> = [
        "pre", "script", "style", "textarea"
    ]

    private struct HTMLContainer: Equatable {
        let quoteDepth: Int
        let listIndent: Int?
    }

    private struct HTMLLineView {
        let text: String
        let sourceOffset: Int
        let container: HTMLContainer
        let belongsToContainer: Bool
    }

    private struct HTMLBlockStart {
        let type: MarkdownHTMLBlockType
        let tagName: String?
        let terminator: String?
    }

    static func htmlBlocks(
        in text: String,
        codeBlockRanges suppliedCodeBlockRanges: [NSRange]? = nil
    ) -> [MarkdownHTMLBlock] {
        let lines = markdownLines(in: text)
        let codeRanges = mergedRanges(
            (suppliedCodeBlockRanges ?? codeBlockRanges(in: text))
                + frontMatterRanges(in: text)
        )
        var blocks: [MarkdownHTMLBlock] = []
        var lineIndex = 0
        var codeRangeIndex = 0
        var paragraphOpen = false

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            while codeRangeIndex < codeRanges.count,
                  NSMaxRange(codeRanges[codeRangeIndex]) <= line.range.location {
                codeRangeIndex += 1
            }

            if codeRangeIndex < codeRanges.count,
               NSIntersectionRange(
                codeRanges[codeRangeIndex],
                line.contentRange
               ).length > 0 {
                let codeRange = codeRanges[codeRangeIndex]
                paragraphOpen = false
                while lineIndex < lines.count,
                      lines[lineIndex].range.location < NSMaxRange(codeRange) {
                    lineIndex += 1
                }
                continue
            }

            let initialView = htmlLineView(for: line.text)
            let initialText = initialView.text as NSString

            if initialText.trimmingCharacters(in: .whitespaces).isEmpty {
                paragraphOpen = false
                lineIndex += 1
                continue
            }

            guard let start = htmlBlockStart(
                in: initialView.text,
                typeSevenAllowed: paragraphOpen == false
            ) else {
                paragraphOpen = true
                lineIndex += 1
                continue
            }

            let leadingSpaces = leadingHTMLIndent(in: initialView.text)
            let htmlStartInLine = initialView.sourceOffset + leadingSpaces
            let blockStart = line.range.location + htmlStartInLine
            var contentRanges: [NSRange] = []
            var finalLineIndex = lineIndex
            var scanIndex = lineIndex

            while scanIndex < lines.count {
                let candidate = lines[scanIndex]
                let view: HTMLLineView

                if scanIndex == lineIndex {
                    view = initialView
                } else {
                    view = htmlLineView(
                        for: candidate.text,
                        continuing: initialView.container
                    )
                    guard view.belongsToContainer else {
                        break
                    }
                }

                let candidateText = view.text as NSString
                let isBlank = candidateText
                    .trimmingCharacters(in: .whitespaces)
                    .isEmpty

                if scanIndex > lineIndex,
                   (start.type == .blockTag || start.type == .completeTag),
                   isBlank {
                    break
                }

                let contentStart = candidate.range.location + view.sourceOffset
                    + (scanIndex == lineIndex ? leadingSpaces : 0)
                let contentEnd = NSMaxRange(candidate.contentRange)
                if contentEnd > contentStart {
                    contentRanges.append(
                        NSRange(location: contentStart, length: contentEnd - contentStart)
                    )
                }

                finalLineIndex = scanIndex
                scanIndex += 1

                let literalContainerEnded = start.type == .literalContainer
                    && literalHTMLBlockTagNames.contains(where: { name in
                        candidateText.range(
                            of: "</\(name)>",
                            options: .caseInsensitive
                        ).location != NSNotFound
                    })
                let otherBlockEnded = start.type != .literalContainer
                    && start.terminator.map {
                        candidateText.range(of: $0).location != NSNotFound
                    } == true
                if literalContainerEnded || otherBlockEnded {
                    break
                }
            }

            let finalEnd = NSMaxRange(lines[finalLineIndex].contentRange)
            blocks.append(
                MarkdownHTMLBlock(
                    range: NSRange(location: blockStart, length: finalEnd - blockStart),
                    contentRanges: contentRanges,
                    type: start.type,
                    tagName: start.tagName,
                    isDisallowed: start.tagName.map {
                        disallowedRawHTMLTags.contains($0.lowercased())
                    } ?? false
                )
            )
            paragraphOpen = false
            lineIndex = max(scanIndex, lineIndex + 1)
        }

        return blocks
    }

    static func indentedCodeBlockRanges(
        in text: String,
        excluding protectedRanges: [NSRange] = []
    ) -> [NSRange] {
        let lines = markdownLines(in: text)
        let frontMatterRanges = frontMatterRanges(in: text)
        var ranges: [NSRange] = []
        var index = 0
        var paragraphOpen = false

        while index < lines.count {
            let line = lines[index]
            if isRange(line.range, intersecting: protectedRanges)
                || isRange(line.contentRange, intersecting: frontMatterRanges) {
                paragraphOpen = false
                index += 1
                continue
            }
            if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                paragraphOpen = false
                index += 1
                continue
            }

            guard isIndentedCodeLine(line.text), paragraphOpen == false else {
                paragraphOpen = isParagraphBlockLine(line.text) == false
                index += 1
                continue
            }

            let start = line.range.location
            var lastContentLine = index
            index += 1

            while index < lines.count {
                let line = lines[index]
                if isRange(line.range, intersecting: protectedRanges) {
                    break
                }
                if isIndentedCodeLine(line.text) {
                    lastContentLine = index
                    index += 1
                } else if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                } else {
                    break
                }
            }

            let end = NSMaxRange(lines[lastContentLine].contentRange)
            ranges.append(NSRange(location: start, length: end - start))
            paragraphOpen = false
        }

        return ranges
    }

    static func inlineTokens(
        in text: String,
        codeBlockRanges suppliedCodeBlockRanges: [NSRange]? = nil,
        indentedCodeBlockRanges suppliedIndentedCodeBlockRanges: [NSRange]? = nil,
        htmlBlocks suppliedHTMLBlocks: [MarkdownHTMLBlock]? = nil
    ) -> MarkdownInlineTokens {
        let nsText = text as NSString
        let fencedCodeRanges = suppliedCodeBlockRanges ?? codeBlockRanges(in: text)
        let blocks = suppliedHTMLBlocks ?? htmlBlocks(
            in: text,
            codeBlockRanges: fencedCodeRanges
        )
        let exclusions = mergedRanges(
            fencedCodeRanges
                + (suppliedIndentedCodeBlockRanges ?? [])
                + indentedCodeBlockRanges(in: text)
                + frontMatterRanges(in: text)
                + blocks.map(\.range)
        )
        var codeSpans: [MarkdownCodeSpan] = []
        var htmlSpans: [MarkdownHTMLSpan] = []
        var exclusionIndex = 0
        var location = 0

        while location < nsText.length {
            while exclusionIndex < exclusions.count,
                  NSMaxRange(exclusions[exclusionIndex]) <= location {
                exclusionIndex += 1
            }

            if exclusionIndex < exclusions.count,
               location >= exclusions[exclusionIndex].location {
                location = NSMaxRange(exclusions[exclusionIndex])
                continue
            }

            let limit = exclusionIndex < exclusions.count
                ? exclusions[exclusionIndex].location
                : nsText.length
            let character = nsText.character(at: location)

            if character == 0x60,
               isEscapedDelimiter(at: location, in: text) == false {
                let openingLength = backtickRunLength(at: location, in: nsText, limit: limit)
                if let span = codeSpan(
                    openingLocation: location,
                    openingLength: openingLength,
                    in: nsText,
                    limit: limit
                ) {
                    codeSpans.append(span)
                    location = NSMaxRange(span.range)
                    continue
                }
                location += openingLength
                continue
            }

            if character == 0x3C,
               isEscapedDelimiter(at: location, in: text) == false,
               let span = rawHTMLSpan(at: location, in: nsText, limit: limit) {
                htmlSpans.append(span)
                location = NSMaxRange(span.range)
                continue
            }

            location += 1
        }

        return MarkdownInlineTokens(
            codeSpans: codeSpans,
            htmlSpans: htmlSpans,
            safeHTMLElements: makeSafeInlineHTMLElements(
                in: nsText,
                htmlSpans: htmlSpans
            )
        )
    }

    static func inlineCodeSpans(in text: String) -> [MarkdownCodeSpan] {
        inlineTokens(in: text).codeSpans
    }

    static func rawHTMLSpans(in text: String) -> [MarkdownHTMLSpan] {
        inlineTokens(in: text).htmlSpans
    }

    static func safeInlineHTMLElements(in text: String) -> [MarkdownInlineHTMLElement] {
        inlineTokens(in: text).safeHTMLElements
    }

    private struct OpenInlineHTMLElement {
        let tag: MarkdownInlineHTMLTag
        let range: NSRange
        let disallowedSpanCount: Int
    }

    /// Builds only complete, correctly nested elements from the closed render
    /// set. A filtered tag inside a candidate prevents that candidate from
    /// reaching the render pass. Unknown tags remain literal but do not stop a
    /// safe outer element from rendering its ordinary text.
    private static func makeSafeInlineHTMLElements(
        in text: NSString,
        htmlSpans: [MarkdownHTMLSpan]
    ) -> [MarkdownInlineHTMLElement] {
        var elements: [MarkdownInlineHTMLElement] = []
        var stack: [OpenInlineHTMLElement] = []
        var disallowedSpanCount = 0
        var disallowedContainerStack: [String] = []

        for span in htmlSpans {
            if span.isDisallowed {
                disallowedSpanCount += 1
                if let name = span.tagName {
                    switch span.kind {
                    case .openTag:
                        if isSelfClosingHTMLSpan(span.range, in: text) == false {
                            disallowedContainerStack.append(name.lowercased())
                        }
                    case .closingTag:
                        if let matchingIndex = disallowedContainerStack.lastIndex(
                            of: name.lowercased()
                        ) {
                            disallowedContainerStack.removeSubrange(matchingIndex...)
                        }
                    case .comment, .processingInstruction, .declaration, .cdata:
                        break
                    }
                }
                continue
            }

            guard let name = span.tagName,
                  let tag = MarkdownInlineHTMLTag(rawValue: name.lowercased()),
                  disallowedContainerStack.isEmpty else {
                continue
            }

            switch span.kind {
            case .openTag:
                if tag == .lineBreak {
                    elements.append(
                        MarkdownInlineHTMLElement(
                            tag: tag,
                            range: span.range,
                            openingTagRange: span.range,
                            contentRange: NSRange(
                                location: NSMaxRange(span.range),
                                length: 0
                            ),
                            closingTagRange: nil
                        )
                    )
                } else if isSelfClosingHTMLSpan(span.range, in: text) == false {
                    stack.append(
                        OpenInlineHTMLElement(
                            tag: tag,
                            range: span.range,
                            disallowedSpanCount: disallowedSpanCount
                        )
                    )
                }

            case .closingTag:
                guard tag != .lineBreak,
                      let matchingIndex = stack.lastIndex(where: { $0.tag == tag }) else {
                    continue
                }

                // A closing tag may only pair with the top element. Remove the
                // whole malformed suffix so a crossing pair cannot swallow
                // later source.
                guard matchingIndex == stack.count - 1 else {
                    stack.removeSubrange(matchingIndex...)
                    continue
                }

                let opening = stack.removeLast()
                guard opening.disallowedSpanCount == disallowedSpanCount else {
                    continue
                }

                let contentStart = NSMaxRange(opening.range)
                let elementEnd = NSMaxRange(span.range)
                guard span.range.location >= contentStart else {
                    continue
                }

                elements.append(
                    MarkdownInlineHTMLElement(
                        tag: tag,
                        range: NSRange(
                            location: opening.range.location,
                            length: elementEnd - opening.range.location
                        ),
                        openingTagRange: opening.range,
                        contentRange: NSRange(
                            location: contentStart,
                            length: span.range.location - contentStart
                        ),
                        closingTagRange: span.range
                    )
                )

            case .comment, .processingInstruction, .declaration, .cdata:
                continue
            }
        }

        return elements
    }

    private static func isSelfClosingHTMLSpan(
        _ range: NSRange,
        in text: NSString
    ) -> Bool {
        guard range.length >= 2, NSMaxRange(range) <= text.length else {
            return false
        }

        return text.character(at: NSMaxRange(range) - 2) == 0x2F
    }

    static func htmlProtectionRanges(in text: String) -> [NSRange] {
        let fencedCodeRanges = codeBlockRanges(in: text)
        let blocks = htmlBlocks(in: text, codeBlockRanges: fencedCodeRanges)
        let tokens = inlineTokens(
            in: text,
            codeBlockRanges: fencedCodeRanges,
            htmlBlocks: blocks
        )
        return mergedRanges(
            frontMatterRanges(in: text)
                + blocks.map(\.range)
                + tokens.htmlSpans.map(\.range)
        )
    }

    static func inlineParsingText(in text: String) -> String {
        let fencedCodeRanges = codeBlockRanges(in: text)
        let blocks = htmlBlocks(in: text, codeBlockRanges: fencedCodeRanges)
        let tokens = inlineTokens(
            in: text,
            codeBlockRanges: fencedCodeRanges,
            htmlBlocks: blocks
        )
        let protectedRanges = fencedCodeRanges
            + indentedCodeBlockRanges(in: text)
            + frontMatterRanges(in: text)
            + blocks.map(\.range)
            + tokens.codeSpans.map(\.range)
            + tokens.htmlSpans.map(\.range)
        return textByMasking(protectedRanges, in: text)
    }

    static func textByMasking(_ ranges: [NSRange], in text: String) -> String {
        let nsText = text as NSString
        let masked = NSMutableString(string: text)

        for range in mergedRanges(ranges).reversed() {
            guard range.location >= 0, NSMaxRange(range) <= nsText.length else {
                continue
            }

            var segmentEnd = NSMaxRange(range)
            var location = NSMaxRange(range)

            while location > range.location {
                location -= 1
                let character = nsText.character(at: location)
                if character == 0x0A || character == 0x0D {
                    if segmentEnd > location + 1 {
                        replaceWithMask(
                            NSRange(location: location + 1, length: segmentEnd - location - 1),
                            in: masked
                        )
                    }
                    segmentEnd = location
                }
            }

            if segmentEnd > range.location {
                replaceWithMask(
                    NSRange(location: range.location, length: segmentEnd - range.location),
                    in: masked
                )
            }
        }

        return masked as String
    }

    private static func replaceWithMask(_ range: NSRange, in text: NSMutableString) {
        guard range.length > 0 else { return }
        text.replaceCharacters(
            in: range,
            with: String(repeating: "\u{FFFC}", count: range.length)
        )
    }

    private static func htmlBlockStart(
        in line: String,
        typeSevenAllowed: Bool
    ) -> HTMLBlockStart? {
        let nsLine = line as NSString
        let indentation = leadingHTMLIndent(in: line)
        guard indentation < nsLine.length,
              nsLine.character(at: indentation) == 0x3C else {
            return nil
        }

        let remainder = nsLine.substring(from: indentation)
        let lower = remainder.lowercased()

        for name in literalHTMLBlockTagNames where lower.hasPrefix("<\(name)") {
            let boundary = name.utf16.count + 1
            if boundary == (remainder as NSString).length
                || isHTMLTagBoundary(at: boundary, in: remainder as NSString, allowSlash: false) {
                return HTMLBlockStart(
                    type: .literalContainer,
                    tagName: name,
                    terminator: "</\(name)>"
                )
            }
        }

        if remainder.hasPrefix("<!--") {
            return HTMLBlockStart(type: .comment, tagName: nil, terminator: "-->")
        }
        if remainder.hasPrefix("<?") {
            return HTMLBlockStart(
                type: .processingInstruction,
                tagName: nil,
                terminator: "?>"
            )
        }
        if remainder.hasPrefix("<![CDATA[") {
            return HTMLBlockStart(type: .cdata, tagName: nil, terminator: "]]>")
        }
        if (remainder as NSString).length >= 3,
           remainder.hasPrefix("<!"),
           isASCIILetter((remainder as NSString).character(at: 2)) {
            return HTMLBlockStart(type: .declaration, tagName: nil, terminator: ">")
        }

        if let name = blockTagName(in: remainder), htmlBlockTagNames.contains(name) {
            return HTMLBlockStart(type: .blockTag, tagName: name, terminator: nil)
        }

        guard typeSevenAllowed,
              let span = rawHTMLSpan(
                at: indentation,
                in: nsLine,
                limit: nsLine.length
              ),
              span.kind == .openTag || span.kind == .closingTag,
              span.kind != .openTag
                || span.tagName.map({ literalHTMLBlockTagNames.contains($0) }) == false else {
            return nil
        }

        let suffixRange = NSRange(
            location: NSMaxRange(span.range),
            length: nsLine.length - NSMaxRange(span.range)
        )
        let suffix = nsLine.substring(with: suffixRange)
        guard suffix.allSatisfy({ $0 == " " || $0 == "\t" }) else {
            return nil
        }

        return HTMLBlockStart(
            type: .completeTag,
            tagName: span.tagName,
            terminator: nil
        )
    }

    private static func blockTagName(in text: String) -> String? {
        let nsText = text as NSString
        var location = 1
        if location < nsText.length, nsText.character(at: location) == 0x2F {
            location += 1
        }
        guard location < nsText.length, isASCIILetter(nsText.character(at: location)) else {
            return nil
        }

        let start = location
        while location < nsText.length, isHTMLTagNameCharacter(nsText.character(at: location)) {
            location += 1
        }
        let name = nsText.substring(
            with: NSRange(location: start, length: location - start)
        ).lowercased()
        guard location == nsText.length
            || isHTMLTagBoundary(at: location, in: nsText, allowSlash: true) else {
            return nil
        }
        return name
    }

    private static func isHTMLTagBoundary(
        at location: Int,
        in text: NSString,
        allowSlash: Bool
    ) -> Bool {
        guard location < text.length else { return true }
        let character = text.character(at: location)
        if character == 0x20 || character == 0x09 || character == 0x3E {
            return true
        }
        return allowSlash
            && character == 0x2F
            && location + 1 < text.length
            && text.character(at: location + 1) == 0x3E
    }

    private static func leadingHTMLIndent(in line: String) -> Int {
        let nsLine = line as NSString
        var indentation = 0
        while indentation < min(3, nsLine.length),
              nsLine.character(at: indentation) == 0x20 {
            indentation += 1
        }
        if indentation < nsLine.length, nsLine.character(at: indentation) == 0x20 {
            return 0
        }
        return indentation
    }

    private static func htmlLineView(
        for line: String,
        continuing container: HTMLContainer? = nil
    ) -> HTMLLineView {
        let nsLine = line as NSString
        var location = 0
        var quoteDepth = 0

        func skipUpToThreeSpaces(_ start: Int) -> Int {
            var cursor = start
            var count = 0
            while cursor < nsLine.length, count < 3,
                  nsLine.character(at: cursor) == 0x20 {
                cursor += 1
                count += 1
            }
            return cursor
        }

        while true {
            let marker = skipUpToThreeSpaces(location)
            guard marker < nsLine.length, nsLine.character(at: marker) == 0x3E else {
                break
            }
            location = marker + 1
            if location < nsLine.length {
                let next = nsLine.character(at: location)
                if next == 0x20 || next == 0x09 {
                    location += 1
                }
            }
            quoteDepth += 1
        }

        if let container {
            guard quoteDepth == container.quoteDepth else {
                return HTMLLineView(
                    text: line,
                    sourceOffset: 0,
                    container: container,
                    belongsToContainer: false
                )
            }

            if let listIndent = container.listIndent {
                let remainder = nsLine.substring(from: location)
                if remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                    return HTMLLineView(
                        text: "",
                        sourceOffset: nsLine.length,
                        container: container,
                        belongsToContainer: true
                    )
                }

                var indentation = 0
                while location + indentation < nsLine.length,
                      nsLine.character(at: location + indentation) == 0x20 {
                    indentation += 1
                }
                guard indentation >= listIndent else {
                    return HTMLLineView(
                        text: line,
                        sourceOffset: 0,
                        container: container,
                        belongsToContainer: false
                    )
                }
                location += listIndent
            }

            return HTMLLineView(
                text: nsLine.substring(from: location),
                sourceOffset: location,
                container: container,
                belongsToContainer: true
            )
        }

        let quoteOffset = location
        let listMarkerStart = skipUpToThreeSpaces(location)
        if let markerEnd = listMarkerEnd(at: listMarkerStart, in: nsLine) {
            var contentStart = markerEnd
            var spacing = 0
            while contentStart < nsLine.length, spacing < 4 {
                let character = nsLine.character(at: contentStart)
                guard character == 0x20 || character == 0x09 else { break }
                contentStart += 1
                spacing += 1
            }
            if spacing > 0 {
                let indent = contentStart - quoteOffset
                let container = HTMLContainer(quoteDepth: quoteDepth, listIndent: indent)
                return HTMLLineView(
                    text: nsLine.substring(from: contentStart),
                    sourceOffset: contentStart,
                    container: container,
                    belongsToContainer: true
                )
            }
        }

        let sourceOffset = quoteDepth > 0 ? quoteOffset : 0
        let container = HTMLContainer(quoteDepth: quoteDepth, listIndent: nil)
        return HTMLLineView(
            text: nsLine.substring(from: sourceOffset),
            sourceOffset: sourceOffset,
            container: container,
            belongsToContainer: true
        )
    }

    private static func listMarkerEnd(at location: Int, in text: NSString) -> Int? {
        guard location < text.length else { return nil }
        let character = text.character(at: location)
        if character == 0x2D || character == 0x2B || character == 0x2A {
            return location + 1
        }

        var cursor = location
        var digitCount = 0
        while cursor < text.length, digitCount < 9,
              isASCIIDigit(text.character(at: cursor)) {
            cursor += 1
            digitCount += 1
        }
        guard digitCount > 0, cursor < text.length else { return nil }
        let delimiter = text.character(at: cursor)
        return delimiter == 0x2E || delimiter == 0x29 ? cursor + 1 : nil
    }

    private static func isIndentedCodeLine(_ line: String) -> Bool {
        let nsLine = line as NSString
        if nsLine.length > 0, nsLine.character(at: 0) == 0x09 {
            let remainder = nsLine.substring(from: 1)
            return isListMarkerLine(remainder) == false
        }
        guard nsLine.length >= 4 else { return false }
        guard (0..<4).allSatisfy({ nsLine.character(at: $0) == 0x20 }) else {
            return false
        }
        return isListMarkerLine(nsLine.substring(from: 4)) == false
    }

    private static func isListMarkerLine(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return cachedRegex(#"^(?:[-+*]|[0-9]{1,9}[.)])[ \t]+"#)
            .firstMatch(in: line, range: range) != nil
    }

    private static func isParagraphBlockLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return true }
        if isListMarkerLine(trimmed) { return true }
        if trimmed.hasPrefix(">") || trimmed.hasPrefix("```")
            || trimmed.hasPrefix("~~~") {
            return true
        }
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        if cachedRegex(#"^#{1,6}(?:[ \t]+|$)"#)
            .firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        return cachedRegex(#"^(?:={1,}|-{3,}|\*{3,}|_{3,})[ \t]*$"#)
            .firstMatch(in: trimmed, range: range) != nil
    }

    private static func rawHTMLSpan(
        at start: Int,
        in text: NSString,
        limit: Int
    ) -> MarkdownHTMLSpan? {
        guard start >= 0, start < limit,
              text.character(at: start) == 0x3C else {
            return nil
        }

        if hasPrefix("<!-->", at: start, in: text, limit: limit) {
            return makeHTMLSpan(
                range: NSRange(location: start, length: 5),
                kind: .comment,
                tagName: nil
            )
        }
        if hasPrefix("<!--->", at: start, in: text, limit: limit) {
            return makeHTMLSpan(
                range: NSRange(location: start, length: 6),
                kind: .comment,
                tagName: nil
            )
        }
        if hasPrefix("<!--", at: start, in: text, limit: limit),
           let end = endOfSequence("-->", after: start + 4, in: text, limit: limit) {
            return makeHTMLSpan(
                range: NSRange(location: start, length: end - start),
                kind: .comment,
                tagName: nil
            )
        }
        if hasPrefix("<?", at: start, in: text, limit: limit),
           let end = endOfSequence("?>", after: start + 2, in: text, limit: limit) {
            return makeHTMLSpan(
                range: NSRange(location: start, length: end - start),
                kind: .processingInstruction,
                tagName: nil
            )
        }
        if hasPrefix("<![CDATA[", at: start, in: text, limit: limit),
           let end = endOfSequence("]]>", after: start + 9, in: text, limit: limit) {
            return makeHTMLSpan(
                range: NSRange(location: start, length: end - start),
                kind: .cdata,
                tagName: nil
            )
        }
        if start + 2 < limit,
           hasPrefix("<!", at: start, in: text, limit: limit),
           isASCIILetter(text.character(at: start + 2)),
           let closing = firstCharacter(0x3E, after: start + 3, in: text, limit: limit) {
            return makeHTMLSpan(
                range: NSRange(location: start, length: closing - start + 1),
                kind: .declaration,
                tagName: nil
            )
        }

        var location = start + 1
        var kind = MarkdownHTMLSpanKind.openTag
        if location < limit, text.character(at: location) == 0x2F {
            kind = .closingTag
            location += 1
        }
        guard location < limit, isASCIILetter(text.character(at: location)) else {
            return nil
        }

        let nameStart = location
        while location < limit, isHTMLTagNameCharacter(text.character(at: location)) {
            location += 1
        }
        let name = text.substring(
            with: NSRange(location: nameStart, length: location - nameStart)
        ).lowercased()

        if kind == .closingTag {
            guard let afterWhitespace = consumeHTMLWhitespace(
                from: location,
                in: text,
                limit: limit
            ), afterWhitespace < limit,
                  text.character(at: afterWhitespace) == 0x3E else {
                return nil
            }
            return makeHTMLSpan(
                range: NSRange(location: start, length: afterWhitespace - start + 1),
                kind: kind,
                tagName: name
            )
        }

        while location < limit {
            let beforeWhitespace = location
            guard let afterWhitespace = consumeHTMLWhitespace(
                from: location,
                in: text,
                limit: limit
            ) else {
                return nil
            }
            let hadWhitespace = afterWhitespace > beforeWhitespace
            location = afterWhitespace

            if location < limit, text.character(at: location) == 0x3E {
                return makeHTMLSpan(
                    range: NSRange(location: start, length: location - start + 1),
                    kind: kind,
                    tagName: name
                )
            }
            if location + 1 < limit,
               text.character(at: location) == 0x2F,
               text.character(at: location + 1) == 0x3E {
                return makeHTMLSpan(
                    range: NSRange(location: start, length: location - start + 2),
                    kind: kind,
                    tagName: name
                )
            }

            guard hadWhitespace,
                  location < limit,
                  isHTMLAttributeNameStart(text.character(at: location)) else {
                return nil
            }
            location += 1
            while location < limit,
                  isHTMLAttributeNameCharacter(text.character(at: location)) {
                location += 1
            }

            let nameEnd = location
            guard let afterNameWhitespace = consumeHTMLWhitespace(
                from: location,
                in: text,
                limit: limit
            ) else {
                return nil
            }
            if afterNameWhitespace < limit,
               text.character(at: afterNameWhitespace) == 0x3D {
                location = afterNameWhitespace + 1
                guard let afterEqualsWhitespace = consumeHTMLWhitespace(
                    from: location,
                    in: text,
                    limit: limit
                ) else {
                    return nil
                }
                location = afterEqualsWhitespace
                guard let valueEnd = consumeHTMLAttributeValue(
                    from: location,
                    in: text,
                    limit: limit
                ) else {
                    return nil
                }
                location = valueEnd
            } else {
                location = nameEnd
            }
        }

        return nil
    }

    private static func makeHTMLSpan(
        range: NSRange,
        kind: MarkdownHTMLSpanKind,
        tagName: String?
    ) -> MarkdownHTMLSpan {
        MarkdownHTMLSpan(
            range: range,
            kind: kind,
            tagName: tagName,
            isDisallowed: tagName.map {
                disallowedRawHTMLTags.contains($0.lowercased())
            } ?? false
        )
    }

    private static func consumeHTMLWhitespace(
        from start: Int,
        in text: NSString,
        limit: Int
    ) -> Int? {
        var location = start
        var lineEndingCount = 0

        while location < limit {
            let character = text.character(at: location)
            if character == 0x20 || character == 0x09 {
                location += 1
            } else if character == 0x0D || character == 0x0A {
                lineEndingCount += 1
                guard lineEndingCount <= 1 else { return nil }
                if character == 0x0D, location + 1 < limit,
                   text.character(at: location + 1) == 0x0A {
                    location += 2
                } else {
                    location += 1
                }
            } else {
                break
            }
        }

        return location
    }

    private static func consumeHTMLAttributeValue(
        from start: Int,
        in text: NSString,
        limit: Int
    ) -> Int? {
        guard start < limit else { return nil }
        let first = text.character(at: start)

        if first == 0x22 || first == 0x27 {
            var location = start + 1
            while location < limit {
                if text.character(at: location) == first {
                    return location + 1
                }
                location += 1
            }
            return nil
        }

        var location = start
        while location < limit {
            let character = text.character(at: location)
            if character == 0x20 || character == 0x09
                || character == 0x0D || character == 0x0A
                || character == 0x22 || character == 0x27
                || character == 0x3D || character == 0x3C
                || character == 0x3E || character == 0x60 {
                break
            }
            location += 1
        }
        return location > start ? location : nil
    }

    private static func codeSpan(
        openingLocation: Int,
        openingLength: Int,
        in text: NSString,
        limit: Int
    ) -> MarkdownCodeSpan? {
        var location = openingLocation + openingLength

        while location < limit {
            guard text.character(at: location) == 0x60 else {
                location += 1
                continue
            }

            let runLength = backtickRunLength(at: location, in: text, limit: limit)
            if runLength == openingLength {
                let opening = NSRange(location: openingLocation, length: openingLength)
                let closing = NSRange(location: location, length: openingLength)
                return MarkdownCodeSpan(
                    range: NSRange(
                        location: openingLocation,
                        length: NSMaxRange(closing) - openingLocation
                    ),
                    openingDelimiterRange: opening,
                    contentRange: NSRange(
                        location: NSMaxRange(opening),
                        length: closing.location - NSMaxRange(opening)
                    ),
                    closingDelimiterRange: closing
                )
            }
            location += runLength
        }

        return nil
    }

    private static func backtickRunLength(
        at start: Int,
        in text: NSString,
        limit: Int
    ) -> Int {
        var location = start
        while location < limit, text.character(at: location) == 0x60 {
            location += 1
        }
        return location - start
    }

    private static func hasPrefix(
        _ prefix: String,
        at location: Int,
        in text: NSString,
        limit: Int
    ) -> Bool {
        let length = (prefix as NSString).length
        guard location + length <= limit else { return false }
        return text.substring(
            with: NSRange(location: location, length: length)
        ) == prefix
    }

    private static func endOfSequence(
        _ sequence: String,
        after location: Int,
        in text: NSString,
        limit: Int
    ) -> Int? {
        let searchRange = NSRange(location: location, length: max(0, limit - location))
        let match = text.range(of: sequence, options: [], range: searchRange)
        return match.location == NSNotFound ? nil : NSMaxRange(match)
    }

    private static func firstCharacter(
        _ character: unichar,
        after location: Int,
        in text: NSString,
        limit: Int
    ) -> Int? {
        var cursor = location
        while cursor < limit {
            if text.character(at: cursor) == character {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { first, second in
                first.location == second.location
                    ? first.length < second.length
                    : first.location < second.location
            }
        var merged: [NSRange] = []

        for range in sorted {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func isASCIILetter(_ character: unichar) -> Bool {
        (character >= 0x41 && character <= 0x5A)
            || (character >= 0x61 && character <= 0x7A)
    }

    private static func isASCIIDigit(_ character: unichar) -> Bool {
        character >= 0x30 && character <= 0x39
    }

    private static func isHTMLTagNameCharacter(_ character: unichar) -> Bool {
        isASCIILetter(character) || isASCIIDigit(character) || character == 0x2D
    }

    private static func isHTMLAttributeNameStart(_ character: unichar) -> Bool {
        isASCIILetter(character) || character == 0x5F || character == 0x3A
    }

    private static func isHTMLAttributeNameCharacter(_ character: unichar) -> Bool {
        isHTMLAttributeNameStart(character)
            || isASCIIDigit(character)
            || character == 0x2E
            || character == 0x2D
    }
}
