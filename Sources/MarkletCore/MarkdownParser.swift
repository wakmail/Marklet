import Foundation

struct MarkdownLine {
    let range: NSRange
    let contentRange: NSRange
    let text: String
}

struct MarkdownCodeBlock {
    let range: NSRange
    let openingFenceRange: NSRange
    let closingFenceRange: NSRange?
    let interiorRange: NSRange
    let infoString: String
    let blockquoteDepth: Int
}

struct MarkdownFrontMatter: Equatable {
    let range: NSRange
    let openingDelimiterRange: NSRange
    let closingDelimiterRange: NSRange
    let bodyRange: NSRange
}

enum MarkdownParser {
    /// A destination in parentheses with one balanced inner pair. Capture
    /// group 1 is the destination.
    static let markdownDestinationPattern = #"\(((?:[^()\n]|\([^()\n]*\))+)\)"#
    static let markdownLinkPattern = #"(?<!!)\[([^\[\]\n]*)\]"#
        + markdownDestinationPattern
    static let markdownImagePattern = #"!\[([^\]\n]*)\]"#
        + markdownDestinationPattern
    static let markdownLinkedImagePattern = #"\["#
        + markdownImagePattern
        + #"\]"#
        + markdownDestinationPattern

    // The title line must hold at least one non-space character. Asserting
    // that with a lookahead and then taking the line in one greedy run keeps
    // the match linear. Writing it inline as `[^\n\r]*\S[^\n\r]*` is quadratic
    // on a very long line, because the engine retries the `\S` at every
    // position, which made typing in a document with no newlines unusable.
    static let setextHeadingPattern = #"(?m)^(?=[^\n\r]*\S)([^\n\r]*)\r?\n([ \t]{0,3}(=+|-+)[ \t]*)$"#
    /// Group 1: quote markers (one `>` per nesting level), group 2: content.
    /// Content may be empty so bare `>` continuation lines join quote runs.
    static let blockquotePattern = #"(?m)^((?:>[ \t]?)+)([^\n\r]*)$"#
    static let listItemPattern = #"(?m)^([ \t]*(?:[-*+]|\d+[.)]))([ \t]+)(.*)$"#
    static let loneUnorderedListItemPattern = #"(?m)^([ \t]*[-*])$"#
    /// Bare URLs and email addresses (autolinks). Parentheses are allowed in
    /// the URL body so `wiki/Foo_(bar)` links whole; trailing punctuation and
    /// unbalanced closing parens are trimmed by `trimmedAutolinkRange`, which
    /// every consumer must apply to the raw match.
    static let autolinkPattern = #"(?:https?://[^\s<>\[\]]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"#

    static func frontMatter(in text: String) -> MarkdownFrontMatter? {
        let nsText = text as NSString
        guard nsText.length > 0 else {
            return nil
        }

        let openingLineRange = nsText.lineRange(
            for: NSRange(location: 0, length: 0)
        )
        let openingLine = markdownLine(for: openingLineRange, in: nsText)
        guard isFrontMatterOpeningDelimiter(openingLine.text),
              NSMaxRange(openingLineRange) < nsText.length else {
            return nil
        }

        var closingLine: MarkdownLine?
        var location = NSMaxRange(openingLineRange)
        while location < nsText.length {
            let lineRange = nsText.lineRange(
                for: NSRange(location: location, length: 0)
            )
            let line = markdownLine(for: lineRange, in: nsText)
            if isFrontMatterClosingDelimiter(line.text) {
                closingLine = line
                break
            }
            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else {
                break
            }
            location = nextLocation
        }

        guard let closingLine else {
            return nil
        }

        let bodyStart = NSMaxRange(openingLine.range)
        return MarkdownFrontMatter(
            range: NSRange(
                location: 0,
                length: NSMaxRange(closingLine.range)
            ),
            openingDelimiterRange: openingLine.contentRange,
            closingDelimiterRange: closingLine.contentRange,
            bodyRange: NSRange(
                location: bodyStart,
                length: max(0, closingLine.range.location - bodyStart)
            )
        )
    }

    static func frontMatterRanges(in text: String) -> [NSRange] {
        frontMatter(in: text).map { [$0.range] } ?? []
    }

    private static func isFrontMatterOpeningDelimiter(_ line: String) -> Bool {
        line.range(of: #"^---[ \t]*$"#, options: .regularExpression) != nil
    }

    private static func isFrontMatterClosingDelimiter(_ line: String) -> Bool {
        line.range(of: #"^(?:---|\.\.\.)[ \t]*$"#, options: .regularExpression) != nil
    }

    /// GFM style trailing trim for an autolink match: strip trailing
    /// punctuation, and strip trailing `)` only while the link holds more
    /// closing than opening parens, so "see https://x.com/a_(b))." links
    /// through `(b)` but sheds the sentence's own paren and period.
    static func trimmedAutolinkRange(_ range: NSRange, in text: NSString) -> NSRange {
        let punctuation: Set<unichar> = [0x2E, 0x2C, 0x3B, 0x3A, 0x21, 0x3F, 0x27, 0x22, 0x60]
        var length = range.length

        while length > 0 {
            let last = text.character(at: range.location + length - 1)

            if punctuation.contains(last) {
                length -= 1
                continue
            }

            if last == 0x29 {
                var balance = 0
                for offset in 0..<length {
                    switch text.character(at: range.location + offset) {
                    case 0x28: balance += 1
                    case 0x29: balance -= 1
                    default: break
                    }
                }
                if balance < 0 {
                    length -= 1
                    continue
                }
            }

            break
        }

        return NSRange(location: range.location, length: length)
    }
    /// Block math: `$$` opening a line through `$$` closing a line; covers
    /// both single-line `$$e=mc^2$$` and fenced multi-line form. Group 1 is
    /// the LaTeX content. Two guards keep the content from overrunning its
    /// closing delimiter:
    ///   - it cannot cross a blank line (blank lines are illegal inside TeX
    ///     math anyway); without that stop, a malformed closing fence like
    ///     `$$dd` sends the lazy match hunting into the next paragraph,
    ///     swallowing the following block's opening `$$` and folding stray
    ///     text into the rendered formula.
    ///   - it cannot contain `$$`; without that stop, a line with two display
    ///     spans like `$$a$$ and $$b$$` matches from the first `$$` to the
    ///     last (the closing anchor `$` forces the run to the line-final
    ///     delimiter), folding the prose between them into one formula. With
    ///     the guard such a line yields no false merged block. LaTeX content
    ///     never contains `$$`, so real formulas are unaffected.
    static let blockMathPattern = #"(?ms)^[ \t]*\$\$((?:(?!\n[ \t]*\n)(?!\$\$).)+?)\$\$[ \t]*$"#

    /// LaTeX content of a block math source (`$$ ... $$` stripped).
    static func blockMathLatex(_ blockText: String) -> String? {
        let trimmed = blockText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 5 else {
            return nil
        }

        return String(trimmed.dropFirst(2).dropLast(2))
    }

    static func blockMathRanges(
        in text: String,
        htmlBlockRanges suppliedHTMLBlockRanges: [NSRange]? = nil
    ) -> [NSRange] {
        let regex = cachedRegex(blockMathPattern)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let codeRanges = codeBlockRanges(in: text)
        let indentedCodeRanges = indentedCodeBlockRanges(in: text)
        let frontMatterRanges = frontMatterRanges(in: text)
        let htmlRanges = suppliedHTMLBlockRanges
            ?? htmlBlocks(in: text, codeBlockRanges: codeRanges).map(\.range)

        return regex
            .matches(in: text, range: fullRange)
            .map(\.range)
            // Intersection, not containment: a `$$` inside a fence pairing
            // with a `$$` right after it straddles the fence boundary, is
            // not contained, and would swallow the closing fence (same
            // defect class as the Setext closing fence bug).
            .filter {
                isRange(
                    $0,
                    intersecting: codeRanges + htmlRanges + indentedCodeRanges + frontMatterRanges
                ) == false
            }
    }

    /// Inline math (`$ ... $`) spans outside code blocks, inline code, block
    /// math, and tables. Scanner-based: single-`$` delimiters on one line
    /// with no unescaped `$` in the content, plus a content heuristic that
    /// rejects currency ("$5", "$1,000.50") and plain prose so dollar signs
    /// in normal text never become math.
    static func inlineMathRanges(
        in text: String,
        htmlProtectionRanges suppliedHTMLProtectionRanges: [NSRange]? = nil,
        blockMathRanges suppliedBlockMathRanges: [NSRange]? = nil,
        tableBlockRanges suppliedTableBlockRanges: [NSRange]? = nil
    ) -> [NSRange] {
        let nsText = text as NSString
        let len = nsText.length

        guard len >= 3, text.contains("$") else {
            return []
        }

        var exclusions = codeBlockRanges(in: text)
        exclusions += indentedCodeBlockRanges(in: text)
        exclusions += frontMatterRanges(in: text)
        exclusions += suppliedHTMLProtectionRanges ?? htmlProtectionRanges(in: text)
        exclusions += suppliedBlockMathRanges ?? blockMathRanges(in: text)
        exclusions += suppliedTableBlockRanges ?? tableBlockRanges(in: text)
        exclusions += cachedRegex(#"`[^`\n]+`"#)
            .matches(in: text, range: NSRange(location: 0, length: len))
            .map(\.range)

        let dollar: unichar = 0x24
        let backslash: unichar = 0x5C
        var results: [NSRange] = []
        var i = 0

        while i < len - 1 {
            guard nsText.character(at: i) == dollar else {
                i += 1
                continue
            }

            // Not part of a `$$` run, not escaped `\$`.
            if i > 0, nsText.character(at: i - 1) == dollar
                || nsText.character(at: i - 1) == backslash {
                i += 1
                continue
            }
            if nsText.character(at: i + 1) == dollar {
                i += 2
                continue
            }

            // Find the closing `$` on the same line.
            var closing = -1
            var k = i + 1
            while k < len {
                let ch = nsText.character(at: k)
                if ch == 0x0A || ch == 0x0D {
                    break
                }
                if ch == dollar {
                    if nsText.character(at: k - 1) == backslash {
                        k += 1
                        continue
                    }
                    if k + 1 < len, nsText.character(at: k + 1) == dollar {
                        break
                    }
                    closing = k
                    break
                }
                k += 1
            }

            guard closing > i + 1 else {
                i += 1
                continue
            }

            let range = NSRange(location: i, length: closing - i + 1)
            let content = nsText.substring(
                with: NSRange(location: i + 1, length: closing - i - 1)
            )

            if isInlineMathContent(content),
               exclusions.allSatisfy({ NSIntersectionRange(range, $0).length == 0 }) {
                results.append(range)
                i = closing + 1
            } else {
                i += 1
            }
        }

        return results
    }

    /// Rejects currency-looking and trivially short non-mathy `$…$` content
    /// so prose isn't misread as math.
    private static func isInlineMathContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false, isCurrencyLike(trimmed) == false else {
            return false
        }

        let mathyMatches = mathyCharCount(trimmed)
        if mathyMatches == 0 {
            return trimmed.count <= 3 && isAllAsciiLetters(trimmed)
        }

        let tokenCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        if mathyMatches >= 3 { return tokenCount <= 120 }
        if mathyMatches == 2 { return tokenCount <= 40 }
        return tokenCount <= 6
    }

    /// A plain signed/thousands-grouped/decimal number (`50`, `1,000.50`,
    /// `-5`), so currency amounts aren't math.
    private static func isCurrencyLike(_ s: String) -> Bool {
        let u = Array(s.utf16)
        let n = u.count

        func digit(_ x: Int) -> Bool { x >= 0 && x < n && u[x] >= 0x30 && u[x] <= 0x39 }

        var i = 0
        if i < n, u[i] == 0x2B || u[i] == 0x2D { i += 1 }  // leading + / -

        guard digit(i) else {
            return false
        }

        while i < n {
            if digit(i) {
                i += 1
            } else if u[i] == 0x2C, digit(i + 1), digit(i + 2), digit(i + 3), digit(i + 4) == false {
                i += 4  // a strict `,DDD` thousands group
            } else {
                break
            }
        }

        if i < n, u[i] == 0x2E {  // optional `.DDD+` decimal part
            i += 1
            guard digit(i) else {
                return false
            }
            while digit(i) { i += 1 }
        }

        return i == n
    }

    /// Count of "mathy" characters: `\ ^ _ { } = + - * / < >`.
    private static func mathyCharCount(_ s: String) -> Int {
        let mathy: Set<unichar> = [0x5C, 0x5E, 0x5F, 0x7B, 0x7D, 0x3D, 0x2B, 0x2D, 0x2A, 0x2F, 0x3C, 0x3E]
        var count = 0
        for u in s.utf16 where mathy.contains(u) {
            count += 1
        }
        return count
    }

    /// True when `s` is one or more ASCII letters only.
    private static func isAllAsciiLetters(_ s: String) -> Bool {
        let u = Array(s.utf16)

        guard u.isEmpty == false else {
            return false
        }

        for x in u where ((x >= 0x41 && x <= 0x5A) || (x >= 0x61 && x <= 0x7A)) == false {
            return false
        }

        return true
    }

    private static let regexLock = NSLock()
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]

    static func cachedRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        let key = options.rawValue == 0 ? pattern : "\(pattern)|\(options.rawValue)"
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[key] { return cached }
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        regexCache[key] = regex
        return regex
    }

    static func codeBlocks(in text: String) -> [MarkdownCodeBlock] {
        codeAndHTMLBlocks(in: text).codeBlocks
    }

    static func codeAndHTMLBlocks(
        in text: String
    ) -> (codeBlocks: [MarkdownCodeBlock], htmlBlocks: [MarkdownHTMLBlock]) {
        let frontMatterRanges = frontMatterRanges(in: text)
        let candidates = rawFencedCodeBlocks(in: text).filter {
            isRange($0.range, intersecting: frontMatterRanges) == false
        }
        guard candidates.isEmpty == false else {
            return ([], htmlBlocks(in: text, codeBlockRanges: frontMatterRanges))
        }

        let initialHTMLBlocks = htmlBlocks(
            in: text,
            codeBlockRanges: candidates.map(\.range) + frontMatterRanges
        )
        let initiallyFiltered = codeBlocks(candidates, outside: initialHTMLBlocks)
        guard initiallyFiltered.count != candidates.count else {
            return (candidates, initialHTMLBlocks)
        }

        let refinedHTMLBlocks = htmlBlocks(
            in: text,
            codeBlockRanges: initiallyFiltered.map(\.range) + frontMatterRanges
        )
        return (codeBlocks(candidates, outside: refinedHTMLBlocks), refinedHTMLBlocks)
    }

    private static func codeBlocks(
        _ candidates: [MarkdownCodeBlock],
        outside htmlBlocks: [MarkdownHTMLBlock]
    ) -> [MarkdownCodeBlock] {
        candidates.filter { codeBlock in
            htmlBlocks.contains { htmlBlock in
                htmlBlock.range.location < codeBlock.range.location
                    && NSIntersectionRange(htmlBlock.range, codeBlock.range).length > 0
            } == false
        }
    }

    private static func rawFencedCodeBlocks(in text: String) -> [MarkdownCodeBlock] {
        let lines = markdownLines(in: text)
        let frontMatterRanges = frontMatterRanges(in: text)
        let textLength = (text as NSString).length
        var blocks: [MarkdownCodeBlock] = []
        var opening: (line: MarkdownLine, fence: CodeFence)?
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if let current = opening {
                if current.fence.blockquoteDepth > 0,
                   blockquoteFenceContent(in: line.text).depth < current.fence.blockquoteDepth {
                    blocks.append(
                        makeCodeBlock(
                            openingLine: current.line,
                            closingLine: nil,
                            fence: current.fence,
                            textLength: line.range.location
                        )
                    )
                    opening = nil
                    continue
                }

                guard isClosingFence(line.text, for: current.fence) else {
                    index += 1
                    continue
                }

                blocks.append(
                    makeCodeBlock(
                        openingLine: current.line,
                        closingLine: line,
                        fence: current.fence,
                        textLength: textLength
                    )
                )
                opening = nil
            } else if isRange(line.contentRange, intersecting: frontMatterRanges) {
                index += 1
                continue
            } else if let fence = openingFence(in: line.text) {
                opening = (line, fence)
            }
            index += 1
        }

        if let opening {
            blocks.append(
                makeCodeBlock(
                    openingLine: opening.line,
                    closingLine: nil,
                    fence: opening.fence,
                    textLength: textLength
                )
            )
        }

        return blocks
    }

    static func codeBlockRanges(in text: String) -> [NSRange] {
        codeBlocks(in: text).map(\.range)
    }

    static func codeBlock(matching range: NSRange, in text: String) -> MarkdownCodeBlock? {
        let nsText = text as NSString
        guard range.location >= 0, range.length > 0,
              NSMaxRange(range) <= nsText.length else {
            return nil
        }

        let firstLineRange = nsText.lineRange(
            for: NSRange(location: range.location, length: 0)
        )
        let openingLine = markdownLine(for: firstLineRange, in: nsText)
        guard let fence = openingFence(in: openingLine.text) else { return nil }

        let lastLocation = max(range.location, NSMaxRange(range) - 1)
        let lastLineRange = nsText.lineRange(
            for: NSRange(location: lastLocation, length: 0)
        )
        let lastLine = markdownLine(for: lastLineRange, in: nsText)
        let closingLine = lastLine.range.location > openingLine.range.location
            && NSMaxRange(lastLine.contentRange) == NSMaxRange(range)
            && isClosingFence(lastLine.text, for: fence)
            ? lastLine
            : nil
        let block = makeCodeBlock(
            openingLine: openingLine,
            closingLine: closingLine,
            fence: fence,
            textLength: NSMaxRange(range)
        )

        return block.range == range ? block : nil
    }

    private struct CodeFence {
        let marker: unichar
        let length: Int
        let infoString: String
        let blockquoteDepth: Int
    }

    private static func openingFence(in line: String) -> CodeFence? {
        let quoted = blockquoteFenceContent(in: line)
        let nsLine = quoted.content as NSString
        var index = 0
        var indentation = 0

        while index < nsLine.length, nsLine.character(at: index) == 0x20 {
            indentation += 1
            guard indentation <= 3 else { return nil }
            index += 1
        }

        guard index < nsLine.length else { return nil }
        let marker = nsLine.character(at: index)
        guard marker == 0x60 || marker == 0x7E else { return nil }

        let markerStart = index
        while index < nsLine.length, nsLine.character(at: index) == marker {
            index += 1
        }

        let markerLength = index - markerStart
        guard markerLength >= 3 else { return nil }

        let remainder = nsLine.substring(from: index)
        if marker == 0x60, remainder.contains("`") {
            return nil
        }

        return CodeFence(
            marker: marker,
            length: markerLength,
            infoString: remainder.trimmingCharacters(in: .whitespaces),
            blockquoteDepth: quoted.depth
        )
    }

    private static func isClosingFence(_ line: String, for opening: CodeFence) -> Bool {
        let quoted = blockquoteFenceContent(in: line)
        guard quoted.depth == opening.blockquoteDepth else { return false }

        let nsLine = quoted.content as NSString
        var index = 0
        var indentation = 0

        while index < nsLine.length, nsLine.character(at: index) == 0x20 {
            indentation += 1
            guard indentation <= 3 else { return false }
            index += 1
        }

        let markerStart = index
        while index < nsLine.length, nsLine.character(at: index) == opening.marker {
            index += 1
        }

        guard index - markerStart >= opening.length else { return false }

        while index < nsLine.length {
            let character = nsLine.character(at: index)
            guard character == 0x20 || character == 0x09 else { return false }
            index += 1
        }

        return true
    }

    private static func blockquoteFenceContent(
        in line: String
    ) -> (content: String, depth: Int) {
        let nsLine = line as NSString
        var location = 0
        var depth = 0

        while location < nsLine.length {
            let prefixStart = location
            var spaces = 0
            while location < nsLine.length,
                  nsLine.character(at: location) == 0x20,
                  spaces < 4 {
                spaces += 1
                location += 1
            }
            guard spaces <= 3,
                  location < nsLine.length,
                  nsLine.character(at: location) == 0x3E else {
                location = prefixStart
                break
            }

            depth += 1
            location += 1
            if location < nsLine.length {
                let character = nsLine.character(at: location)
                if character == 0x20 || character == 0x09 {
                    location += 1
                }
            }
        }

        guard depth > 0 else { return (line, 0) }
        return (nsLine.substring(from: location), depth)
    }

    private static func makeCodeBlock(
        openingLine: MarkdownLine,
        closingLine: MarkdownLine?,
        fence: CodeFence,
        textLength: Int
    ) -> MarkdownCodeBlock {
        let blockEnd = closingLine.map { NSMaxRange($0.contentRange) } ?? textLength
        let range = NSRange(
            location: openingLine.range.location,
            length: blockEnd - openingLine.range.location
        )
        let openingEnd = min(NSMaxRange(openingLine.range), blockEnd)
        let openingFenceRange = NSRange(
            location: openingLine.range.location,
            length: openingEnd - openingLine.range.location
        )
        let closingFenceRange = closingLine.map { line in
            NSRange(
                location: line.contentRange.location,
                length: min(NSMaxRange(line.contentRange), blockEnd) - line.contentRange.location
            )
        }
        let interiorStart = NSMaxRange(openingFenceRange)
        let interiorEnd = closingLine?.contentRange.location ?? blockEnd
        let interiorRange = NSRange(
            location: interiorStart,
            length: max(0, interiorEnd - interiorStart)
        )

        return MarkdownCodeBlock(
            range: range,
            openingFenceRange: openingFenceRange,
            closingFenceRange: closingFenceRange,
            interiorRange: interiorRange,
            infoString: fence.infoString,
            blockquoteDepth: fence.blockquoteDepth
        )
    }

    private static func markdownLine(for lineRange: NSRange, in text: NSString) -> MarkdownLine {
        let rawLine = text.substring(with: lineRange)
        let lineText = rawLine.trimmingCharacters(in: .newlines)
        return MarkdownLine(
            range: lineRange,
            contentRange: NSRange(
                location: lineRange.location,
                length: (lineText as NSString).length
            ),
            text: lineText
        )
    }

    // MARK: - Blockquote runs and callouts

    /// Contiguous blockquote line paragraphs merged into runs, excluding
    /// quotes inside fenced code blocks.
    static func blockquoteRunRanges(
        in text: String,
        htmlBlockRanges suppliedHTMLBlockRanges: [NSRange]? = nil
    ) -> [NSRange] {
        let nsText = text as NSString
        let codeBlocks = codeBlocks(in: text)
        let codeRanges = codeBlocks.map(\.range)
        let frontMatterRanges = frontMatterRanges(in: text)
        let unquotedCodeRanges = codeBlocks
            .filter { $0.blockquoteDepth == 0 }
            .map(\.range)
        let htmlRanges = suppliedHTMLBlockRanges
            ?? htmlBlocks(in: text, codeBlockRanges: codeRanges).map(\.range)
        let regex = cachedRegex(blockquotePattern)
        let matches = regex
            .matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .filter {
                isRange(
                    $0.range,
                    intersecting: unquotedCodeRanges + htmlRanges + frontMatterRanges
                ) == false
            }
        let matchesByLocation = Dictionary(
            uniqueKeysWithValues: matches.map { ($0.range.location, $0) }
        )
        let protectedRanges = codeRanges + htmlRanges + frontMatterRanges

        var runs: [NSRange] = []
        var currentRunIndex: Int?
        var acceptsLazyContinuation = false

        for line in markdownLines(in: text) {
            if let match = matchesByLocation[line.range.location] {
                if let currentRunIndex,
                   line.range.location == NSMaxRange(runs[currentRunIndex]) {
                    runs[currentRunIndex] = NSUnionRange(
                        runs[currentRunIndex],
                        line.range
                    )
                } else {
                    runs.append(line.range)
                    currentRunIndex = runs.count - 1
                }

                let content = nsText.substring(with: match.range(at: 2))
                acceptsLazyContinuation = content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
                    && isParagraphContinuationText(content)
            } else if let currentRunIndex,
                      line.range.location == NSMaxRange(runs[currentRunIndex]),
                      acceptsLazyContinuation,
                      isRange(line.contentRange, intersecting: protectedRanges) == false,
                      isParagraphContinuationText(line.text) {
                runs[currentRunIndex] = NSUnionRange(
                    runs[currentRunIndex],
                    line.range
                )
            } else {
                currentRunIndex = nil
                acceptsLazyContinuation = false
            }
        }
        return runs
    }

    static func paragraphContinuationRanges(
        after initialRange: NSRange,
        initialContent: String,
        in text: String
    ) -> [NSRange] {
        let nsText = text as NSString
        guard initialRange.location != NSNotFound,
              initialRange.length > 0,
              NSMaxRange(initialRange) <= nsText.length,
              isParagraphContinuationText(initialContent) else {
            return []
        }

        let initialParagraph = nsText.paragraphRange(for: initialRange)
        var ranges: [NSRange] = []
        var location = NSMaxRange(initialParagraph)
        while location < nsText.length {
            let lineRange = nsText.paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let line = nsText.substring(with: lineRange)
                .trimmingCharacters(in: .newlines)
            guard isParagraphContinuationText(line) else {
                break
            }
            ranges.append(lineRange)

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else {
                break
            }
            location = nextLocation
        }
        return ranges
    }

    static func listItemRanges(
        in text: String,
        htmlBlockRanges suppliedHTMLBlockRanges: [NSRange]? = nil,
        loneMarkersStartLists: Bool = false
    ) -> [NSRange] {
        let nsText = text as NSString
        let codeRanges = codeBlockRanges(in: text)
        let frontMatterRanges = frontMatterRanges(in: text)
        let htmlRanges = suppliedHTMLBlockRanges
            ?? htmlBlocks(in: text, codeBlockRanges: codeRanges).map(\.range)
        let protectedRanges = codeRanges + htmlRanges + frontMatterRanges
        let fullRange = NSRange(location: 0, length: nsText.length)

        var matches = cachedRegex(listItemPattern)
            .matches(in: text, range: fullRange)
        if loneMarkersStartLists {
            matches += cachedRegex(loneUnorderedListItemPattern)
                .matches(in: text, range: fullRange)
        }

        return matches
            .sorted { $0.range.location < $1.range.location }
            .compactMap { match in
                guard isRange(match.range, intersecting: protectedRanges) == false,
                      isThematicBreakLine(
                          nsText.substring(with: match.range)
                      ) == false else {
                    return nil
                }

                let lineRange = nsText.paragraphRange(for: match.range)
                let continuations = paragraphContinuationRanges(
                    after: match.range,
                    initialContent: match.numberOfRanges > 3
                        ? nsText.substring(with: match.range(at: 3))
                        : "",
                    in: text
                )
                guard let last = continuations.last else {
                    return lineRange
                }
                return NSUnionRange(lineRange, last)
            }
    }

    private static func isParagraphContinuationText(_ line: String) -> Bool {
        let nsLine = line as NSString
        var location = 0
        var indentation = 0
        while location < nsLine.length {
            let character = nsLine.character(at: location)
            guard character == 0x20 || character == 0x09 else {
                break
            }
            indentation += character == 0x09 ? 4 : 1
            location += 1
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }
        if indentation >= 4 {
            return true
        }

        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        let interruptingPattern = #"^(?:#{1,6}(?:[ \t]+|$)|>|(?:`{3,}|~{3,})|(?:[-+*]|\d+[.)])(?:[ \t]+|$)|(?:=+|-+)[ \t]*$|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$)"#
        return cachedRegex(interruptingPattern)
            .firstMatch(in: trimmed, range: range) == nil
    }

    private static func isThematicBreakLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        let pattern = #"^([-*_])(?:[ \t]*\1){2,}[ \t]*$"#
        return cachedRegex(pattern).firstMatch(in: trimmed, range: range) != nil
    }

    /// A blockquote run whose first line starts with a known `[!type]`
    /// callout marker (GitHub/Obsidian admonition syntax).
    struct CalloutRun: Equatable {
        /// The whole blockquote run, including trailing newline.
        let runRange: NSRange
        /// Lowercased known type, e.g. "note".
        let type: String
        /// The `[!type]` marker characters.
        let markerRange: NSRange
        /// Custom title text after the marker on the same line, if any.
        let titleRange: NSRange?
    }

    /// Known callout types and aliases (GitHub's five plus Obsidian's
    /// defaults). Unknown types stay plain blockquotes, matching GitHub.
    static let knownCalloutTypes: Set<String> = [
        "note", "info", "todo",
        "tip", "hint", "abstract", "summary", "tldr",
        "important",
        "warning", "attention",
        "caution",
        "success", "check", "done",
        "question", "help", "faq",
        "failure", "fail", "missing",
        "danger", "error", "bug",
        "example",
        "quote", "cite"
    ]

    /// Callout runs in `text`: blockquote runs whose first line's content is
    /// `[!type]` (case-insensitive, known type) plus an optional title.
    static func calloutRuns(
        in text: String,
        blockquoteRunRanges suppliedBlockquoteRunRanges: [NSRange]? = nil
    ) -> [CalloutRun] {
        let nsText = text as NSString
        let firstLineRegex = cachedRegex(
            #"^((?:>[ \t]?)+)(\[!([A-Za-z][A-Za-z0-9_-]*)\])[ \t]*([^\n\r]*?)[ \t]*$"#,
            options: [.anchorsMatchLines]
        )

        let blockquoteRanges = suppliedBlockquoteRunRanges ?? blockquoteRunRanges(in: text)
        return blockquoteRanges.compactMap { run in
            let firstLineRange = nsText.lineRange(for: NSRange(location: run.location, length: 0))
            guard let match = firstLineRegex.firstMatch(in: text, range: firstLineRange) else {
                return nil
            }

            let type = nsText.substring(with: match.range(at: 3)).lowercased()
            guard knownCalloutTypes.contains(type) else {
                return nil
            }

            let titleRange = match.range(at: 4)
            return CalloutRun(
                runRange: run,
                type: type,
                markerRange: match.range(at: 2),
                titleRange: titleRange.length > 0 ? titleRange : nil
            )
        }
    }

    static func markdownLines(in text: String) -> [MarkdownLine] {
        let nsText = text as NSString
        var lines: [MarkdownLine] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let rawLine = nsText.substring(with: lineRange)
            let lineText = rawLine.trimmingCharacters(in: .newlines)
            let contentRange = NSRange(
                location: lineRange.location,
                length: (lineText as NSString).length
            )

            lines.append(
                MarkdownLine(
                    range: lineRange,
                    contentRange: contentRange,
                    text: lineText
                )
            )

            let nextLocation = NSMaxRange(lineRange)
            if nextLocation <= location {
                break
            }

            location = nextLocation
        }

        return lines
    }

    static func setextUnderlineRanges(
        in text: String,
        htmlBlockRanges suppliedHTMLBlockRanges: [NSRange]? = nil
    ) -> [NSRange] {
        let regex = cachedRegex(setextHeadingPattern)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let cbRanges = codeBlockRanges(in: text)
        // A Setext underline needs a paragraph line above it. A line inside an
        // indented code block is not one, so `----` under indented code is a
        // thematic break rather than a heading underline. Fenced code was
        // already excluded here; indented code was not.
        let indentedRanges = indentedCodeBlockRanges(in: text)
        let frontMatterRanges = frontMatterRanges(in: text)
        let htmlRanges = suppliedHTMLBlockRanges
            ?? htmlBlocks(in: text, codeBlockRanges: cbRanges).map(\.range)

        return regex
            .matches(in: text, range: fullRange)
            .compactMap { match in
                // The two-line match straddles a code block's closing fence
                // when the title line is that fence, so `containedIn` misses
                // it; use intersection so the fence is never read as a Setext
                // underline (which would suppress its thematic-break styling).
                guard isRange(
                    match.range,
                    intersecting: cbRanges + indentedRanges + htmlRanges + frontMatterRanges
                ) == false,
                      isSetextTitleCandidate(nsText.substring(with: match.range(at: 1))) else {
                    return nil
                }
                return match.range(at: 2)
            }
    }

    static func tableBlockRanges(
        in text: String,
        htmlBlockRanges suppliedHTMLBlockRanges: [NSRange]? = nil
    ) -> [NSRange] {
        let lines = markdownLines(in: text)
        let codeRanges = codeBlockRanges(in: text)
        let frontMatterRanges = frontMatterRanges(in: text)
        let htmlRanges = suppliedHTMLBlockRanges
            ?? htmlBlocks(in: text, codeBlockRanges: codeRanges).map(\.range)
        var ranges: [NSRange] = []
        var index = 0

        while index + 1 < lines.count {
            let headerLine = lines[index]
            let delimiterLine = lines[index + 1]

            guard isRange(
                headerLine.contentRange,
                intersecting: codeRanges + htmlRanges + frontMatterRanges
            ) == false,
                  isRange(
                      delimiterLine.contentRange,
                      intersecting: codeRanges + htmlRanges + frontMatterRanges
                  ) == false,
                  isTableHeader(headerLine.text, delimiterLine: delimiterLine.text) else {
                index += 1
                continue
            }

            var endIndex = index + 2
            let columnCount = tableCells(in: headerLine.text).count

            while endIndex < lines.count {
                let line = lines[endIndex]

                guard isRange(
                    line.contentRange,
                    intersecting: codeRanges + htmlRanges + frontMatterRanges
                ) == false,
                      isTableBodyRow(line.text, expectedColumnCount: columnCount) else {
                    break
                }

                endIndex += 1
            }

            let lastLineRange = lines[endIndex - 1].range
            ranges.append(
                NSRange(
                    location: headerLine.range.location,
                    length: NSMaxRange(lastLineRange) - headerLine.range.location
                )
            )

            index = endIndex
        }

        return ranges
    }

    static func isTableHeader(_ headerLine: String, delimiterLine: String) -> Bool {
        let headerCells = tableCells(in: headerLine)
        let delimiterCells = tableCells(in: delimiterLine)

        guard hasUnescapedPipe(in: headerLine),
              hasUnescapedPipe(in: delimiterLine),
              headerCells.count >= 1,
              delimiterCells.count == headerCells.count else {
            return false
        }

        return delimiterCells.allSatisfy(isTableDelimiterCell)
    }

    static func isTableBodyRow(_ line: String, expectedColumnCount: Int) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let cells = tableCells(in: line)

        return trimmedLine.isEmpty == false
            && hasUnescapedPipe(in: line)
            && cells.count == expectedColumnCount
    }

    static func hasUnescapedPipe(in line: String) -> Bool {
        var backslashRun = 0

        for character in line {
            if character == "|", backslashRun % 2 == 0 {
                return true
            }

            if character == "\\" {
                backslashRun += 1
            } else {
                backslashRun = 0
            }
        }

        return false
    }

    static func tableCells(in line: String) -> [String] {
        var cells: [String] = []
        var currentCell = ""
        var backslashRun = 0

        for character in line {
            if character == "|", backslashRun % 2 == 0 {
                cells.append(currentCell)
                currentCell = ""
                backslashRun = 0
                continue
            }

            currentCell.append(character)

            if character == "\\" {
                backslashRun += 1
            } else {
                backslashRun = 0
            }
        }

        cells.append(currentCell)

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.hasPrefix("|"),
           cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeFirst()
        }

        if trimmedLine.hasSuffix("|"),
           cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeLast()
        }

        return cells
    }

    static func isTableDelimiterCell(_ cell: String) -> Bool {
        cell
            .trimmingCharacters(in: .whitespaces)
            .range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }

    static func isSetextTitleCandidate(_ title: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedTitle.isEmpty == false else {
            return false
        }

        // ATX headings are their own element, and list items can't be Setext
        // titles (CommonMark: a Setext title must be a paragraph); without
        // the list check, typing the next `- ` bullet under a list item
        // matches the `-+` underline and repaints the item above as an H2.
        return trimmedTitle.range(
            of: #"^(#{1,6})([ \t]+).+"#,
            options: .regularExpression
        ) == nil
            && trimmedTitle.range(
                of: #"^(?:[-*+]|\d+[.)])(?:[ \t]|$)"#,
                options: .regularExpression
            ) == nil
    }

    static func isRange(_ range: NSRange, containedIn containingRanges: [NSRange]) -> Bool {
        containingRanges.contains { containingRange in
            range.location >= containingRange.location
                && NSMaxRange(range) <= NSMaxRange(containingRange)
        }
    }

    static func isRange(_ range: NSRange, intersecting containingRanges: [NSRange]) -> Bool {
        containingRanges.contains { containingRange in
            NSIntersectionRange(range, containingRange).length > 0
                || (range.length == 0
                    && range.location >= containingRange.location
                    && range.location <= NSMaxRange(containingRange))
        }
    }

    static func isEscapedDelimiter(at location: Int, in text: String) -> Bool {
        let nsText = text as NSString
        guard location > 0, location < nsText.length else {
            return false
        }

        var backslashCount = 0
        var currentLocation = location - 1

        while currentLocation >= 0,
              nsText.character(at: currentLocation) == 92 {
            backslashCount += 1
            currentLocation -= 1
        }

        return backslashCount % 2 == 1
    }

    static func imagePath(from destination: String) -> String? {
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedDestination.hasPrefix("<"),
           let closingIndex = trimmedDestination.firstIndex(of: ">") {
            let path = trimmedDestination[trimmedDestination.index(after: trimmedDestination.startIndex)..<closingIndex]
            return String(path)
        }

        guard trimmedDestination.isEmpty == false else {
            return nil
        }

        let titlePattern = #"^(.+?)[ \t]+(?:\"[^\"\n]*\"|'[^'\n]*'|\([^()\n]*\))[ \t]*$"#
        let fullRange = NSRange(location: 0, length: (trimmedDestination as NSString).length)
        if let match = cachedRegex(titlePattern).firstMatch(
            in: trimmedDestination,
            range: fullRange
        ) {
            return (trimmedDestination as NSString)
                .substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
        }

        return trimmedDestination
    }

    static func parseImageWidth(from altText: String) -> CGFloat? {
        guard let pipeIndex = altText.lastIndex(of: "|") else {
            return nil
        }
        let afterPipe = altText[altText.index(after: pipeIndex)...]
        guard let value = Double(afterPipe.trimmingCharacters(in: .whitespaces)),
              value > 0 else {
            return nil
        }
        return CGFloat(value)
    }

    static func imageAltText(from altText: String) -> String {
        guard let pipeIndex = altText.lastIndex(of: "|") else {
            return altText
        }
        let afterPipe = altText[altText.index(after: pipeIndex)...]
        guard Double(afterPipe.trimmingCharacters(in: .whitespaces)) != nil else {
            return altText
        }
        return String(altText[..<pipeIndex])
    }
}
