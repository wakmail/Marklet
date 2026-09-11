import Foundation

struct MarkdownFootnoteReference: Equatable {
    let label: String
    let range: NSRange
    let labelRange: NSRange
    let number: Int
}

struct MarkdownFootnoteDefinition: Equatable {
    let label: String
    let range: NSRange
    let prefixRange: NSRange
    let labelRange: NSRange
    let initialBodyRange: NSRange
    let continuationRanges: [NSRange]
    let continuationContentRanges: [NSRange]
    let number: Int
}

struct MarkdownFootnotes: Equatable {
    let references: [MarkdownFootnoteReference]
    let definitions: [MarkdownFootnoteDefinition]

    static let empty = MarkdownFootnotes(references: [], definitions: [])

    var constructRanges: [NSRange] {
        references.map(\.range) + definitions.map(\.prefixRange)
    }
}

extension MarkdownParser {
    static let footnoteReferencePattern = #"\[\^([^\]\s]+)\]"#
    static let footnoteDefinitionPattern = #"(?m)^\[\^([^\]\s]+)\]:[ \t]*(.*)$"#

    static func footnoteDefinitionBlockRanges(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [NSRange] {
        footnoteDefinitionCandidates(
            in: text,
            protectedRanges: protectedRanges
        ).map(\.range)
    }

    static func footnotes(
        in text: String,
        codeBlockRanges suppliedCodeBlockRanges: [NSRange]? = nil,
        indentedCodeBlockRanges suppliedIndentedCodeBlockRanges: [NSRange]? = nil,
        inlineCodeSpans suppliedInlineCodeSpans: [MarkdownCodeSpan]? = nil,
        htmlBlocks suppliedHTMLBlocks: [MarkdownHTMLBlock]? = nil,
        htmlSpans suppliedHTMLSpans: [MarkdownHTMLSpan]? = nil,
        mathRanges suppliedMathRanges: [NSRange]? = nil
    ) -> MarkdownFootnotes {
        let fencedCodeRanges = suppliedCodeBlockRanges ?? codeBlockRanges(in: text)
        let blocks = suppliedHTMLBlocks ?? htmlBlocks(
            in: text,
            codeBlockRanges: fencedCodeRanges
        )
        let preliminaryDefinitions = footnoteDefinitionCandidates(
            in: text,
            protectedRanges: fencedCodeRanges + blocks.map(\.range)
        )
        let indentedRanges = suppliedIndentedCodeBlockRanges
            ?? indentedCodeBlockRanges(
                in: text,
                excluding: preliminaryDefinitions.map(\.range)
            )
        let tokens: MarkdownInlineTokens
        if let suppliedInlineCodeSpans, let suppliedHTMLSpans {
            tokens = MarkdownInlineTokens(
                codeSpans: suppliedInlineCodeSpans,
                htmlSpans: suppliedHTMLSpans,
                safeHTMLElements: []
            )
        } else {
            tokens = inlineTokens(
                in: text,
                codeBlockRanges: fencedCodeRanges,
                indentedCodeBlockRanges: indentedRanges,
                htmlBlocks: blocks
            )
        }
        let mathRanges = suppliedMathRanges ?? (
            blockMathRanges(in: text) + inlineMathRanges(in: text)
        )
        let protectedRanges = fencedCodeRanges
            + indentedRanges
            + blocks.map(\.range)
            + tokens.codeSpans.map(\.range)
            + tokens.htmlSpans.map(\.range)
            + mathRanges
        let definitions = preliminaryDefinitions.filter {
            isRange($0.prefixRange, intersecting: protectedRanges) == false
        }
        let parsingText = textByMasking(protectedRanges, in: text)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let definitionReferenceRanges = Set(definitions.map {
            NSRange(location: $0.prefixRange.location, length: $0.prefixRange.length - 1)
        })
        let destinationRanges = footnoteLinkDestinationRanges(in: parsingText)
        let definitionLabels = Set(definitions.map(\.label))

        let candidates = cachedRegex(footnoteReferencePattern)
            .matches(in: parsingText, range: fullRange)
            .compactMap { match -> (label: String, range: NSRange, labelRange: NSRange)? in
                guard definitionReferenceRanges.contains(match.range) == false,
                      isEscapedDelimiter(at: match.range.location, in: text) == false,
                      isRange(match.range, intersecting: destinationRanges) == false else {
                    return nil
                }
                return (
                    nsText.substring(with: match.range(at: 1)),
                    match.range,
                    match.range(at: 1)
                )
            }
        let matchedCandidates = candidates.filter { definitionLabels.contains($0.label) }

        var numbers: [String: Int] = [:]
        var nextNumber = 1
        for candidate in matchedCandidates where numbers[candidate.label] == nil {
            numbers[candidate.label] = nextNumber
            nextNumber += 1
        }
        for definition in definitions where numbers[definition.label] == nil {
            numbers[definition.label] = nextNumber
            nextNumber += 1
        }

        return MarkdownFootnotes(
            references: matchedCandidates.map {
                MarkdownFootnoteReference(
                    label: $0.label,
                    range: $0.range,
                    labelRange: $0.labelRange,
                    number: numbers[$0.label]!
                )
            },
            definitions: definitions.map {
                MarkdownFootnoteDefinition(
                    label: $0.label,
                    range: $0.range,
                    prefixRange: $0.prefixRange,
                    labelRange: $0.labelRange,
                    initialBodyRange: $0.initialBodyRange,
                    continuationRanges: $0.continuationRanges,
                    continuationContentRanges: $0.continuationContentRanges,
                    number: numbers[$0.label]!
                )
            }
        )
    }

    private struct FootnoteDefinitionCandidate {
        let label: String
        let range: NSRange
        let prefixRange: NSRange
        let labelRange: NSRange
        let initialBodyRange: NSRange
        let continuationRanges: [NSRange]
        let continuationContentRanges: [NSRange]
    }

    private static func footnoteDefinitionCandidates(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [FootnoteDefinitionCandidate] {
        let nsText = text as NSString
        let lines = markdownLines(in: text)
        let regex = cachedRegex(footnoteDefinitionPattern)
        var definitions: [FootnoteDefinitionCandidate] = []

        for (index, line) in lines.enumerated() {
            guard isRange(line.contentRange, intersecting: protectedRanges) == false,
                  let match = regex.firstMatch(
                    in: text,
                    range: line.contentRange
                  ),
                  match.range == line.contentRange else {
                continue
            }

            var continuationRanges: [NSRange] = []
            var continuationContentRanges: [NSRange] = []
            var pendingBlankRanges: [NSRange] = []
            var scanIndex = index + 1
            while scanIndex < lines.count {
                let candidate = lines[scanIndex]
                if candidate.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    pendingBlankRanges.append(candidate.range)
                    scanIndex += 1
                    continue
                }

                guard let contentOffset = footnoteContinuationContentOffset(
                    in: candidate.text
                ) else {
                    break
                }
                continuationRanges.append(contentsOf: pendingBlankRanges)
                continuationContentRanges.append(contentsOf: pendingBlankRanges.map { blank in
                    NSRange(location: blank.location, length: 0)
                })
                pendingBlankRanges.removeAll()
                continuationRanges.append(candidate.range)
                continuationContentRanges.append(NSRange(
                    location: candidate.contentRange.location + contentOffset,
                    length: candidate.contentRange.length - contentOffset
                ))
                scanIndex += 1
            }

            let finalRange = continuationRanges.last.map {
                NSUnionRange(line.range, $0)
            } ?? line.range
            let prefixEnd = NSMaxRange(match.range(at: 1)) + 2
            definitions.append(FootnoteDefinitionCandidate(
                label: nsText.substring(with: match.range(at: 1)),
                range: finalRange,
                prefixRange: NSRange(
                    location: match.range.location,
                    length: prefixEnd - match.range.location
                ),
                labelRange: match.range(at: 1),
                initialBodyRange: match.range(at: 2),
                continuationRanges: continuationRanges,
                continuationContentRanges: continuationContentRanges
            ))
        }

        return definitions
    }

    private static func footnoteContinuationContentOffset(in line: String) -> Int? {
        let nsLine = line as NSString
        guard nsLine.length > 0 else {
            return nil
        }
        if nsLine.character(at: 0) == 0x09 {
            return 1
        }
        guard nsLine.length >= 4 else {
            return nil
        }
        return (0..<4).allSatisfy { nsLine.character(at: $0) == 0x20 }
            ? 4
            : nil
    }

    private static func footnoteLinkDestinationRanges(in parsingText: String) -> [NSRange] {
        let fullRange = NSRange(
            location: 0,
            length: (parsingText as NSString).length
        )
        return [markdownLinkPattern, markdownImagePattern].flatMap { pattern in
            cachedRegex(pattern)
                .matches(in: parsingText, range: fullRange)
                .compactMap { match in
                    match.numberOfRanges > 2 ? match.range(at: 2) : nil
                }
        }
    }
}
