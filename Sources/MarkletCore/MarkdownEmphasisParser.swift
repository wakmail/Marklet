import Foundation

extension MarkdownParser {
    enum EmphasisKind: Hashable {
        case emphasis
        case strong
    }

    struct Emphasis: Hashable {
        let kind: EmphasisKind
        let marker: UInt16
        let openingMarkerRange: NSRange
        let closingMarkerRange: NSRange
        let contentRange: NSRange
        let fullRange: NSRange
    }

    private struct EmphasisDelimiter {
        let marker: UInt16
        let range: NSRange
        let canOpen: Bool
        let canClose: Bool
        let linkLabelIndex: Int?
        var consumedFromStart = 0
        var remainingLength: Int
        var previous: Int?
        var next: Int?

        var openingMarkerEnd: Int {
            range.location + consumedFromStart + remainingLength
        }

        var closingMarkerStart: Int {
            range.location + consumedFromStart
        }
    }

    private enum EmphasisCharacterClass {
        case whitespace
        case punctuation
        case other
    }

    private struct EmphasisBottomKey: Hashable {
        let delimiterClass: Int
        let linkLabelIndex: Int?
    }

    /// Parses CommonMark emphasis and strong emphasis from the protected
    /// inline view of `text`. Code and HTML ranges are spaces in that view,
    /// so their delimiters cannot participate while their original source
    /// still supplies the neighboring character used by the flanking rules.
    static func emphasis(
        in text: String,
        loneMarkersStartLists: Bool = false
    ) -> [Emphasis] {
        guard text.contains("*") || text.contains("_") else {
            return []
        }
        let blockMath = blockMathRanges(in: text)
        return emphasis(
            in: text,
            parsingText: inlineParsingText(in: text),
            additionalProtectedRanges: blockMath
                + inlineMathRanges(in: text, blockMathRanges: blockMath),
            loneMarkersStartLists: loneMarkersStartLists
        )
    }

    static func emphasis(
        in text: String,
        parsingText: String,
        additionalProtectedRanges: [NSRange] = [],
        loneMarkersStartLists: Bool = false
    ) -> [Emphasis] {
        guard parsingText.contains("*") || parsingText.contains("_") else {
            return []
        }
        let source = text as NSString
        let linkStructure = emphasisLinkStructure(in: parsingText)
        let autolinkRanges = emphasisAngleAutolinkRanges(in: parsingText)
        let protectedRanges = additionalProtectedRanges
            + linkStructure.protectedRanges
            + autolinkRanges
        let protectedParsingText = protectedRanges.isEmpty
            ? parsingText
            : textByMasking(protectedRanges, in: parsingText)
        let parsingSource = protectedParsingText as NSString
        guard source.length == parsingSource.length, source.length > 0 else {
            return []
        }

        var delimiters: [EmphasisDelimiter] = []
        var location = 0
        var linkLabelCursor = 0

        while location < parsingSource.length {
            let marker = parsingSource.character(at: location)
            guard marker == 0x2A || marker == 0x5F,
                  isEscapedDelimiter(at: location, in: text) == false else {
                location += 1
                continue
            }

            let runStart = location
            repeat {
                location += 1
            } while location < parsingSource.length
                && parsingSource.character(at: location) == marker

            let runLength = location - runStart
            if marker == 0x2A, runLength == 1,
               isListMarkerAsterisk(
                   at: runStart,
                   in: text,
                   loneMarkersStartLists: loneMarkersStartLists
               ) {
                continue
            }
            let before = emphasisCharacter(before: runStart, in: source)
            let after = emphasisCharacter(at: location, in: source)
            let leftFlanking = after != .whitespace
                && (after != .punctuation
                    || before == .whitespace
                    || before == .punctuation)
            let rightFlanking = before != .whitespace
                && (before != .punctuation
                    || after == .whitespace
                    || after == .punctuation)

            let canOpen: Bool
            let canClose: Bool
            if marker == 0x5F {
                canOpen = leftFlanking
                    && (rightFlanking == false || before == .punctuation)
                canClose = rightFlanking
                    && (leftFlanking == false || after == .punctuation)
            } else {
                canOpen = leftFlanking
                canClose = rightFlanking
            }

            while linkLabelCursor < linkStructure.labelRanges.count,
                  NSMaxRange(linkStructure.labelRanges[linkLabelCursor]) <= runStart {
                linkLabelCursor += 1
            }
            let linkLabelIndex = linkLabelCursor < linkStructure.labelRanges.count
                && runStart >= linkStructure.labelRanges[linkLabelCursor].location
                && runStart < NSMaxRange(linkStructure.labelRanges[linkLabelCursor])
                ? linkLabelCursor
                : nil

            let index = delimiters.count
            delimiters.append(
                EmphasisDelimiter(
                    marker: marker,
                    range: NSRange(location: runStart, length: runLength),
                    canOpen: canOpen,
                    canClose: canClose,
                    linkLabelIndex: linkLabelIndex,
                    remainingLength: runLength,
                    previous: index > 0 ? index - 1 : nil,
                    next: nil
                )
            )
            if index > 0 {
                delimiters[index - 1].next = index
            }
        }

        guard delimiters.isEmpty == false else {
            return []
        }

        var matches: [Emphasis] = []
        var scopeBottoms: [Int: Int] = [:]
        for delimiter in delimiters {
            guard let labelIndex = delimiter.linkLabelIndex,
                  scopeBottoms[labelIndex] == nil else {
                continue
            }
            scopeBottoms[labelIndex] = delimiter.previous ?? -1
        }
        var openerBottoms: [EmphasisBottomKey: Int] = [:]
        var closerIndex: Int? = 0

        while let closer = closerIndex {
            guard delimiters[closer].canClose,
                  delimiters[closer].remainingLength > 0 else {
                closerIndex = delimiters[closer].next
                continue
            }

            let bottomKey = emphasisBottomKey(for: delimiters[closer])
            let scopeBottom = delimiters[closer].linkLabelIndex
                .flatMap { scopeBottoms[$0] } ?? -1
            let bottom = openerBottoms[bottomKey] ?? scopeBottom
            var openerIndex = delimiters[closer].previous
            var matchingOpener: Int?

            while let opener = openerIndex, opener > bottom {
                if delimiters[opener].marker == delimiters[closer].marker,
                   delimiters[opener].canOpen,
                   delimiters[opener].remainingLength > 0,
                   delimiters[opener].linkLabelIndex
                    == delimiters[closer].linkLabelIndex,
                   emphasisRuleOfThreeAllows(
                       opener: delimiters[opener],
                       closer: delimiters[closer]
                   ) {
                    matchingOpener = opener
                    break
                }
                openerIndex = delimiters[opener].previous
            }

            guard let opener = matchingOpener else {
                let next = delimiters[closer].next
                openerBottoms[bottomKey] = delimiters[closer].previous
                    ?? scopeBottom
                if delimiters[closer].canOpen == false {
                    unlinkDelimiter(closer, in: &delimiters)
                }
                closerIndex = next
                continue
            }

            let useLength = delimiters[opener].remainingLength >= 2
                && delimiters[closer].remainingLength >= 2 ? 2 : 1
            let openingLocation = delimiters[opener].openingMarkerEnd - useLength
            let closingLocation = delimiters[closer].closingMarkerStart
            let openingRange = NSRange(location: openingLocation, length: useLength)
            let closingRange = NSRange(location: closingLocation, length: useLength)
            let contentRange = NSRange(
                location: NSMaxRange(openingRange),
                length: closingRange.location - NSMaxRange(openingRange)
            )
            let fullRange = NSRange(
                location: openingRange.location,
                length: NSMaxRange(closingRange) - openingRange.location
            )
            matches.append(
                Emphasis(
                    kind: useLength == 2 ? .strong : .emphasis,
                    marker: delimiters[opener].marker,
                    openingMarkerRange: openingRange,
                    closingMarkerRange: closingRange,
                    contentRange: contentRange,
                    fullRange: fullRange
                )
            )

            delimiters[opener].remainingLength -= useLength
            delimiters[closer].remainingLength -= useLength
            delimiters[closer].consumedFromStart += useLength

            removeDelimiters(between: opener, and: closer, in: &delimiters)

            if delimiters[opener].remainingLength == 0 {
                unlinkDelimiter(opener, in: &delimiters)
            }

            if delimiters[closer].remainingLength == 0 {
                let next = delimiters[closer].next
                unlinkDelimiter(closer, in: &delimiters)
                closerIndex = next
            } else {
                closerIndex = closer
            }
        }

        return matches
    }

    private static func emphasisRuleOfThreeAllows(
        opener: EmphasisDelimiter,
        closer: EmphasisDelimiter
    ) -> Bool {
        guard opener.canClose || closer.canOpen else {
            return true
        }

        let sumIsMultipleOfThree = (
            opener.remainingLength + closer.remainingLength
        ) % 3 == 0
        let bothAreMultiplesOfThree = opener.remainingLength % 3 == 0
            && closer.remainingLength % 3 == 0
        return sumIsMultipleOfThree == false || bothAreMultiplesOfThree
    }

    private static func emphasisLinkStructure(
        in parsingText: String
    ) -> (labelRanges: [NSRange], protectedRanges: [NSRange]) {
        guard parsingText.contains("](") else {
            return ([], [])
        }

        let textLength = (parsingText as NSString).length
        let fullRange = NSRange(location: 0, length: textLength)
        let patterns = [
            markdownLinkPattern,
            markdownImagePattern
        ]
        var labels: [NSRange] = []
        var protected: [NSRange] = []

        for pattern in patterns {
            for match in cachedRegex(pattern).matches(
                in: parsingText,
                range: fullRange
            ) {
                let label = match.range(at: 1)
                labels.append(label)
                protected.append(
                    NSRange(
                        location: NSMaxRange(label),
                        length: NSMaxRange(match.range) - NSMaxRange(label)
                    )
                )
            }
        }
        return (
            labels.sorted { $0.location < $1.location },
            protected.sorted { $0.location < $1.location }
        )
    }

    private static func emphasisAngleAutolinkRanges(
        in parsingText: String
    ) -> [NSRange] {
        guard parsingText.contains("<") else {
            return []
        }

        let pattern = #"<(?:[A-Za-z][A-Za-z0-9+.-]{1,31}:[^<>\s]*|[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)>"#
        let fullRange = NSRange(
            location: 0,
            length: (parsingText as NSString).length
        )
        return cachedRegex(pattern)
            .matches(in: parsingText, range: fullRange)
            .map(\.range)
    }

    private static func emphasisBottomKey(
        for closer: EmphasisDelimiter
    ) -> EmphasisBottomKey {
        let markerOffset = closer.marker == 0x2A ? 0 : 6
        let openOffset = closer.canOpen ? 3 : 0
        return EmphasisBottomKey(
            delimiterClass: markerOffset + openOffset
                + closer.remainingLength % 3,
            linkLabelIndex: closer.linkLabelIndex
        )
    }

    private static func removeDelimiters(
        between opener: Int,
        and closer: Int,
        in delimiters: inout [EmphasisDelimiter]
    ) {
        var current = delimiters[opener].next
        while let index = current, index != closer {
            current = delimiters[index].next
            unlinkDelimiter(index, in: &delimiters)
        }
    }

    private static func unlinkDelimiter(
        _ index: Int,
        in delimiters: inout [EmphasisDelimiter]
    ) {
        let previous = delimiters[index].previous
        let next = delimiters[index].next
        if let previous {
            delimiters[previous].next = next
        }
        if let next {
            delimiters[next].previous = previous
        }
        delimiters[index].previous = nil
        delimiters[index].next = nil
    }

    private static func emphasisCharacter(
        before location: Int,
        in text: NSString
    ) -> EmphasisCharacterClass {
        guard location > 0 else {
            return .whitespace
        }

        var scalarLocation = location - 1
        let unit = text.character(at: scalarLocation)
        if unit >= 0xDC00, unit <= 0xDFFF, scalarLocation > 0 {
            let preceding = text.character(at: scalarLocation - 1)
            if preceding >= 0xD800, preceding <= 0xDBFF {
                scalarLocation -= 1
            }
        }
        return emphasisCharacter(at: scalarLocation, in: text)
    }

    private static func emphasisCharacter(
        at location: Int,
        in text: NSString
    ) -> EmphasisCharacterClass {
        guard location >= 0, location < text.length else {
            return .whitespace
        }

        let first = text.character(at: location)
        if first < 0x80 {
            if first == 0x20 || first >= 0x09 && first <= 0x0D {
                return .whitespace
            }
            if first >= 0x21 && first <= 0x2F
                || first >= 0x3A && first <= 0x40
                || first >= 0x5B && first <= 0x60
                || first >= 0x7B && first <= 0x7E {
                return .punctuation
            }
            return .other
        }

        let scalarValue: UInt32
        if first >= 0xD800, first <= 0xDBFF, location + 1 < text.length {
            let second = text.character(at: location + 1)
            if second >= 0xDC00, second <= 0xDFFF {
                scalarValue = 0x10000
                    + (UInt32(first - 0xD800) << 10)
                    + UInt32(second - 0xDC00)
            } else {
                scalarValue = UInt32(first)
            }
        } else {
            scalarValue = UInt32(first)
        }

        guard let scalar = Unicode.Scalar(scalarValue) else {
            return .other
        }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return .whitespace
        }
        if CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar) {
            return .punctuation
        }
        return .other
    }

    static func isListMarkerAsterisk(
        at location: Int,
        in text: String,
        loneMarkersStartLists: Bool = false
    ) -> Bool {
        let source = text as NSString
        guard location != NSNotFound, location < source.length,
              source.character(at: location) == 0x2A else {
            return false
        }

        var index = location - 1
        while index >= 0 {
            let unit = source.character(at: index)
            if unit == 0x0A || unit == 0x0D {
                break
            }
            if unit != 0x20, unit != 0x09 {
                return false
            }
            index -= 1
        }

        let followingIndex = location + 1
        guard followingIndex < source.length else {
            return loneMarkersStartLists
        }
        let following = source.character(at: followingIndex)
        if following == 0x0A || following == 0x0D {
            return loneMarkersStartLists
        }
        guard let scalar = Unicode.Scalar(UInt32(following)) else {
            return false
        }
        return CharacterSet.whitespaces.contains(scalar)
    }
}
