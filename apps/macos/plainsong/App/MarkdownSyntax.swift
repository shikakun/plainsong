import Foundation

/// CommonMarkより緩く読む。複数の行をまとめて読むのは、コードブロックと先頭のフロントマターだけ
/// 正規表現に渡すたびに`String`へ変換するので、変換のたびに全文をコピーする`NSMutableString`ではなく、不変の`NSString`を渡す
nonisolated enum MarkdownSyntax {
    enum Flavor {
        case markdown
        case mdx
    }

    struct Style: OptionSet, Hashable {
        let rawValue: Int

        static let bold = Style(rawValue: 1 << 0)
        static let marker = Style(rawValue: 1 << 1)
        static let code = Style(rawValue: 1 << 2)
        static let monospaced = Style(rawValue: 1 << 3)
        static let unindented = Style(rawValue: 1 << 4)
    }

    struct Run: Equatable {
        var range: NSRange
        var style: Style
    }

    struct Block: Hashable {
        var range: NSRange
        var isClosed: Bool
        var isFrontMatter = false
    }

    private struct Fence {
        let character: unichar
        let length: Int
    }

    private static let backtick = unichar(UInt8(ascii: "`"))
    private static let tilde = unichar(UInt8(ascii: "~"))
    private static let quoteMark = unichar(UInt8(ascii: ">"))
    private static let pipe = unichar(UInt8(ascii: "|"))
    private static let backslash = unichar(UInt8(ascii: "\\"))
    private static let space = unichar(UInt8(ascii: " "))
    private static let tab = unichar(UInt8(ascii: "\t"))

    static func blocks(in string: NSString) -> [Block] {
        var blocks: [Block] = []
        var location = 0
        if let frontMatter = frontMatter(in: string) {
            blocks.append(frontMatter)
            location = NSMaxRange(frontMatter.range)
        }
        var opening: (location: Int, fence: Fence)?
        while location < string.length {
            let (line, contents) = lineRanges(at: location, in: string)
            if let current = opening {
                if isClosingFence(contents, in: string, of: current.fence) {
                    blocks.append(Block(range: NSRange(current.location ..< NSMaxRange(line)), isClosed: true))
                    opening = nil
                }
            } else if let fence = openingFence(contents, in: string) {
                opening = (line.location, fence)
            }
            location = NSMaxRange(line)
        }
        if let opening {
            blocks.append(Block(range: NSRange(opening.location ..< string.length), isClosed: false))
        }
        return blocks
    }

    static func runs(in range: NSRange, of string: NSString, blocks: [Block], flavor: Flavor) -> [Run] {
        let range = string.lineRange(for: range)
        var styles = [Style](repeating: [], count: range.length)
        let add = { (style: Style, styledRange: NSRange) in
            for index in styledRange.location ..< NSMaxRange(styledRange) {
                styles[index - range.location].formUnion(style)
            }
        }
        var blockIndex = blocks.firstIndex { NSMaxRange($0.range) > range.location } ?? blocks.endIndex
        var location = range.location
        while location < NSMaxRange(range) {
            let (line, contents) = lineRanges(at: location, in: string)
            while blockIndex < blocks.endIndex, NSMaxRange(blocks[blockIndex].range) <= line.location {
                blockIndex += 1
            }
            if blockIndex < blocks.endIndex, NSLocationInRange(line.location, blocks[blockIndex].range) {
                addBlockLine(line, of: blocks[blockIndex], add: add)
            } else {
                addLine(contents, of: string, flavor: flavor, add: add)
            }
            location = NSMaxRange(line)
        }

        var runs: [Run] = []
        for (offset, style) in styles.enumerated() where !style.isEmpty {
            if let last = runs.last, last.style == style, NSMaxRange(last.range) == range.location + offset {
                runs[runs.count - 1].range.length += 1
            } else {
                runs.append(Run(range: NSRange(location: range.location + offset, length: 1), style: style))
            }
        }
        return runs
    }

    private static func addBlockLine(_ line: NSRange, of block: Block, add: (Style, NSRange) -> Void) {
        let isFence = line.location == block.range.location
            || (NSMaxRange(line) == NSMaxRange(block.range) && block.isClosed)
        let style: Style = block.isFrontMatter ? [.marker, .monospaced] : isFence ? [.marker, .code] : .code
        add(style.union(.unindented), line)
    }

    private static func addLine(
        _ contents: NSRange,
        of string: NSString,
        flavor: Flavor,
        add: (Style, NSRange) -> Void
    ) {
        if flavor == .mdx, firstMatch(of: mdxStatement, in: contents, of: string) != nil {
            add([.code, .unindented], contents)
            return
        }
        var inline = contents
        let isQuoteMark = { (index: Int) in string.character(at: index) == quoteMark }
        if let quote = firstMatch(of: blockquote, in: inline, of: string) {
            for index in quote.range.location ..< NSMaxRange(quote.range) where isQuoteMark(index) {
                add(.marker, NSRange(location: index, length: 1))
            }
            inline = NSRange(NSMaxRange(quote.range) ..< NSMaxRange(contents))
        }
        let isTableRow = firstMatch(of: tableRow, in: inline, of: string) != nil
        if isTableRow {
            add(.unindented, contents)
            if firstMatch(of: tableDelimiterRow, in: inline, of: string) != nil {
                add([.marker, .monospaced], inline)
                return
            }
        }
        if firstMatch(of: thematicBreak, in: inline, of: string) != nil {
            add(.marker, inline)
            return
        }
        if let heading = firstMatch(of: atxHeading, in: inline, of: string) {
            let marks = heading.range(at: 1)
            add(.unindented, contents)
            add(.monospaced, heading.range)
            add(.marker, marks)
            add(.bold, NSRange(NSMaxRange(marks) ..< NSMaxRange(inline)))
            inline = NSRange(NSMaxRange(heading.range) ..< NSMaxRange(inline))
        } else if let item = firstMatch(of: listItem, in: inline, of: string) {
            add(.unindented, contents)
            add(.monospaced, item.range)
            add(.marker, item.range(at: 1))
            if item.range(at: 2).location != NSNotFound {
                add(.marker, item.range(at: 2))
            }
            inline = NSRange(NSMaxRange(item.range) ..< NSMaxRange(inline))
        }
        let (codeSpans, tags) = addInline(inline, of: string, isTableRow: isTableRow, add: add)
        if isCodeOrHTML(contents, of: string, codeSpans: codeSpans, tags: tags) {
            add(.unindented, contents)
        }
    }

    private static func addInline(
        _ range: NSRange,
        of string: NSString,
        isTableRow: Bool,
        add: (Style, NSRange) -> Void
    ) -> (codeSpans: [NSRange], tags: [NSRange]) {
        let codeSpans = addCodeSpans(in: range, of: string, add: add)
        let isInCode = { (location: Int) in contains(location, in: codeSpans) }
        let isColumnSeparator = { (index: Int) in
            string.character(at: index) == pipe && !isInCode(index)
                && (index == range.location || string.character(at: index - 1) != backslash)
        }
        for index in range.location ..< NSMaxRange(range) where isTableRow && isColumnSeparator(index) {
            add([.marker, .monospaced], NSRange(location: index, length: 1))
        }
        let text = string as String
        let matches = { (expression: NSRegularExpression) in
            expression.matches(in: text, range: range).filter { match in
                !isInCode(match.range.location) && !isInCode(NSMaxRange(match.range) - 1)
            }
        }
        for match in matches(strong) {
            let content = match.range(at: 2)
            add(.marker, NSRange(match.range.location ..< content.location))
            add(.bold, content)
            add(.marker, NSRange(NSMaxRange(content) ..< NSMaxRange(match.range)))
        }
        for match in matches(link) {
            let label = match.range(at: 1)
            add(.marker, NSRange(match.range.location ..< label.location))
            add(.marker, NSRange(NSMaxRange(label) ..< NSMaxRange(match.range)))
        }
        let tags = tag.matches(in: text, range: range).map(\.range).filter { match in
            !codeSpans.contains { NSIntersectionRange($0, match).length > 0 }
        }
        for tag in tags {
            add([.marker, .monospaced], tag)
        }
        return (codeSpans, tags)
    }

    private static func isCodeOrHTML(
        _ contents: NSRange,
        of string: NSString,
        codeSpans: [NSRange],
        tags: [NSRange]
    ) -> Bool {
        guard !codeSpans.isEmpty || !tags.isEmpty else { return false }
        let visible = (contents.location ..< NSMaxRange(contents)).filter { index in
            Unicode.Scalar(string.character(at: index)).map { !CharacterSet.whitespaces.contains($0) } ?? true
        }
        guard let first = visible.first, let last = visible.last else { return false }
        return visible.allSatisfy { contains($0, in: codeSpans) }
            || (contains(first, in: tags) && contains(last, in: tags))
    }

    private static func contains(_ location: Int, in ranges: [NSRange]) -> Bool {
        ranges.contains { NSLocationInRange(location, $0) }
    }

    private static func addCodeSpans(
        in range: NSRange,
        of string: NSString,
        add: (Style, NSRange) -> Void
    ) -> [NSRange] {
        var spans: [NSRange] = []
        let end = NSMaxRange(range)
        let backtickRun = { (start: Int) in
            var index = start
            while index < end, string.character(at: index) == backtick {
                index += 1
            }
            return index - start
        }
        var index = range.location
        while index < end {
            guard string.character(at: index) == backtick else {
                index += 1
                continue
            }
            let length = backtickRun(index)
            let contentStart = index + length
            var search = contentStart
            index = contentStart
            while search < end {
                guard string.character(at: search) == backtick else {
                    search += 1
                    continue
                }
                let closingLength = backtickRun(search)
                if closingLength == length {
                    add([.marker, .code], NSRange(location: contentStart - length, length: length))
                    add(.code, NSRange(contentStart ..< search))
                    add([.marker, .code], NSRange(location: search, length: length))
                    spans.append(NSRange(contentStart - length ..< search + length))
                    index = search + length
                    break
                }
                search += closingLength
            }
        }
        return spans
    }

    private static func frontMatter(in string: NSString) -> Block? {
        guard string.length > 0 else { return nil }
        let (first, firstContents) = lineRanges(at: 0, in: string)
        guard string.substring(with: firstContents) == "---" else { return nil }
        var location = NSMaxRange(first)
        while location < string.length {
            let (line, contents) = lineRanges(at: location, in: string)
            if ["---", "..."].contains(string.substring(with: contents)) {
                return Block(range: NSRange(0 ..< NSMaxRange(line)), isClosed: true, isFrontMatter: true)
            }
            location = NSMaxRange(line)
        }
        return nil
    }

    /// リストの中のコードブロックも読むので、行頭の空白はいくつでもよい
    private static func fence(in contents: NSRange, of string: NSString) -> (fence: Fence, rest: NSRange)? {
        let end = NSMaxRange(contents)
        var index = contents.location
        while index < end, [space, tab].contains(string.character(at: index)) {
            index += 1
        }
        guard index < end else { return nil }
        let character = string.character(at: index)
        guard character == backtick || character == tilde else { return nil }
        let start = index
        while index < end, string.character(at: index) == character {
            index += 1
        }
        guard index - start >= 3 else { return nil }
        return (Fence(character: character, length: index - start), NSRange(index ..< end))
    }

    private static func openingFence(_ contents: NSRange, in string: NSString) -> Fence? {
        guard let (fence, rest) = fence(in: contents, of: string) else { return nil }
        if fence.character == backtick, string.range(of: "`", range: rest).location != NSNotFound {
            return nil
        }
        return fence
    }

    private static func isClosingFence(_ contents: NSRange, in string: NSString, of opening: Fence) -> Bool {
        guard let (fence, rest) = fence(in: contents, of: string),
              fence.character == opening.character,
              fence.length >= opening.length
        else { return false }
        return string.substring(with: rest).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func lineRanges(at location: Int, in string: NSString) -> (line: NSRange, contents: NSRange) {
        var start = 0
        var end = 0
        var contentsEnd = 0
        string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return (NSRange(start ..< end), NSRange(start ..< contentsEnd))
    }
}

private nonisolated extension MarkdownSyntax {
    static func firstMatch(
        of expression: NSRegularExpression,
        in range: NSRange,
        of string: NSString
    ) -> NSTextCheckingResult? {
        expression.firstMatch(in: string as String, options: .anchored, range: range)
    }

    static func expression(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    static let mdxStatement = expression(#"(?:import|export)[ \t]"#)
    /// 行頭の`|`を省いたテーブルは、区切りの行まで見ないと見分けられないので、対象外にする
    static let tableRow = expression(#"[ \t]*\|"#)
    static let tableDelimiterRow = expression(#"[ \t]*\|(?:[ \t]*:?-+:?[ \t]*\|)*[ \t]*:?-+:?[ \t]*\|?[ \t]*$"#)
    static let blockquote = expression(#"[ \t]*(?:>[ \t]?)+"#)
    static let thematicBreak = expression(#"[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    static let atxHeading = expression(#"[ \t]{0,3}(#{1,6})(?:[ \t]+|$)"#)
    static let listItem = expression(#"[ \t]*([-*+]|\d{1,9}[.)])(?:[ \t]+(\[[ xX]\]))?(?:[ \t]+|$)"#)
    /// 和文は記号の前後に空白を入れないので、CommonMarkのflankingの規則は使わない
    static let strong = expression(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let link = expression(#"!?\[([^\]]*)\]\([^()\s]*(?:[ \t]+"[^"]*")?\)"#)
    static let tag = expression(#"<!--.*?-->|</?[A-Za-z][\w.:-]*(?:\s[^<>]*)?/?>"#)
}
