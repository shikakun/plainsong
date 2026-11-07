import Foundation

/// 400字詰めの原稿用紙に組んだときの行を求める。字下げ以外の設定やフォントには左右されない
nonisolated struct ManuscriptPaper: Equatable {
    struct Line: Equatable {
        /// 改行も含めた、UTF-16での長さ
        var length: Int
        /// 字下げとぶら下げも含めた、行が使うマスの数
        var cells: Int
    }

    private struct Unit {
        var length: Int
        var scalar: Unicode.Scalar?

        var isTab: Bool {
            scalar == "\t"
        }
    }

    static let cellsPerLine = 20
    static let linesPerPage = 20
    private static let cellsPerTab = Int(EditorSettings.tabEms)

    private static let hanging = Set("、。".unicodeScalars)
    /// stone_engineのSTKinsoku（MIT License, Copyright 2024 Nihon Design Center）に、全角の！とゝゞを足したもの
    private static let notStarting = Set(
        " ,.?:;!)）]］｝、〕〉》」』】〙〗〟’”｠»ヽヾゝゞァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ々〻？！‼⁇⁈⁉。.™".unicodeScalars
    )
    private static let notEnding = Set("(（[［｛〔〈《「『【〘〖〝‘“｟«\"'".unicodeScalars)

    /// 段落の字下げのマスの数
    var indent = 0

    static func pages(forLines lines: Int) -> Int {
        (lines + linesPerPage - 1) / linesPerPage
    }

    func count(in string: NSString, range: NSRange? = nil) -> Int {
        lines(in: string, range: range).count
    }

    func lines(in string: NSString, range: NSRange? = nil) -> [Line] {
        let range = range ?? NSRange(location: 0, length: string.length)
        let rangeEnd = NSMaxRange(range)
        var lines: [Line] = []
        var location = range.location
        while location < rangeEnd {
            var lineEnd = 0
            var contentsEnd = 0
            string.getLineStart(
                nil,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            lineEnd = min(lineEnd, rangeEnd)
            contentsEnd = min(contentsEnd, rangeEnd)
            let contents = NSRange(location: location, length: contentsEnd - location)
            appendLines(
                of: Self.units(of: contents, in: string),
                indent: indent(ofContents: contents, in: string),
                terminatorLength: lineEnd - contentsEnd,
                to: &lines
            )
            location = lineEnd
        }
        return lines
    }

    /// `location`から始まる行が使うマスの数を返す。TextKitが行を組むたびに呼ぶので、行が決まるだけの文字しか読まない
    func cells(ofLineAt location: Int, in string: NSString) -> Int {
        guard location < string.length else { return 0 }
        var length = Self.cellsPerLine * 3
        while true {
            let end = min(location + length, string.length)
            let contentsEnd = (location ..< end).first { Self.isLineBreak(string.character(at: $0)) } ?? end
            let contents = NSRange(location: location, length: contentsEnd - location)
            let units = Self.units(of: contents, in: string)
            // 次の字とその次の字まで見れば、行の終わりが決まる
            if contentsEnd < end || end == string.length || units.count > Self.cellsPerLine + 2 {
                guard !units.isEmpty else { return 0 }
                let startCells = isParagraphStart(location, in: string) ? indent(ofContents: contents, in: string) : 0
                let lineEnd = Self.lineEnd(from: 0, cells: startCells, in: units)
                return Self.cells(of: 0 ..< lineEnd, from: startCells, in: units)
            }
            length *= 2
        }
    }

    private func isParagraphStart(_ location: Int, in string: NSString) -> Bool {
        guard location > 0 else { return true }
        return Self.isParagraphBreak(string.character(at: location - 1))
    }

    private static func isParagraphBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x85 || character == 0x2029
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        isParagraphBreak(character) || character == 0x2028
    }

    /// U+2028は段落を分けずに行を変えるので、そのあとの行は字下げしない
    private func indent(ofContents contents: NSRange, in string: NSString) -> Int {
        guard indent > 0, contents.length > 0, isParagraphStart(contents.location, in: string),
              ParagraphIndentRules.indents(paragraphStartingWith: string.character(at: contents.location))
        else { return 0 }
        return indent
    }

    /// 縦中横の2桁は、組方向によらず1マスに入れる
    /// 行は語の途中からも始まるので、語の先頭から調べる。2026の後半を2桁とみなさないため
    private static func units(of contents: NSRange, in string: NSString) -> [Unit] {
        var tokenStart = contents.location
        while tokenStart > 0, UprightGlyphs.isHalfWidthGraphic(string.character(at: tokenStart - 1)) {
            tokenStart -= 1
        }
        let searched = NSRange(location: tokenStart, length: NSMaxRange(contents) - tokenStart)
        var tateChuYoko = UprightGlyphs.runs(in: string, range: searched)
            .filter { $0.kind == .tateChuYoko && $0.range.location >= contents.location }
            .map(\.range)[...]
        var units: [Unit] = []
        units.reserveCapacity(contents.length)
        var location = contents.location
        var mergedEnd = 0
        for character in string.substring(with: contents) {
            let length = character.utf16.count
            if location < mergedEnd, !units.isEmpty {
                units[units.count - 1].length += length
            } else {
                if let run = tateChuYoko.first, run.location == location {
                    mergedEnd = NSMaxRange(run)
                    tateChuYoko.removeFirst()
                }
                units.append(Unit(length: length, scalar: character.unicodeScalars.first))
            }
            location += length
        }
        return units
    }

    private func appendLines(
        of units: [Unit],
        indent: Int,
        terminatorLength: Int,
        to lines: inout [Line]
    ) {
        guard !units.isEmpty else {
            lines.append(Line(length: terminatorLength, cells: 0))
            return
        }
        var start = 0
        var startCells = indent
        while start < units.count {
            let end = Self.lineEnd(from: start, cells: startCells, in: units)
            let length = units[start ..< end].reduce(end == units.count ? terminatorLength : 0) { $0 + $1.length }
            lines.append(Line(length: length, cells: Self.cells(of: start ..< end, from: startCells, in: units)))
            start = end
            startCells = 0
        }
    }

    private static func lineEnd(from start: Int, cells startCells: Int, in units: [Unit]) -> Int {
        var end = start
        var cells = startCells
        while end < units.count {
            let width = width(of: units[end], at: cells)
            guard cells + width <= cellsPerLine else { break }
            cells += width
            end += 1
        }
        end = max(end, start + 1)
        guard end < units.count else { return end }
        if canHang(at: end, in: units) {
            return end + 1
        }
        var candidate = end
        while candidate > start, !canBreak(before: candidate, in: units) {
            candidate -= 1
        }
        // 禁則の文字だけが続いて送る先がないときは、マスいっぱいで折り返す
        return candidate > start ? candidate : end
    }

    private static func cells(of range: Range<Int>, from startCells: Int, in units: [Unit]) -> Int {
        units[range].reduce(startCells) { $0 + width(of: $1, at: $0) }
    }

    /// タブは次のタブストップまで進むので、幅は行の中の位置で決まる
    private static func width(of unit: Unit, at cells: Int) -> Int {
        unit.isTab ? cellsPerTab - cells % cellsPerTab : 1
    }

    /// 次の字も行頭に置けないときにぶら下げると、その字の行き場がなくなる
    private static func canHang(at index: Int, in units: [Unit]) -> Bool {
        guard let scalar = units[index].scalar, hanging.contains(scalar) else { return false }
        return index + 1 == units.count || !isNotStarting(units[index + 1])
    }

    private static func canBreak(before index: Int, in units: [Unit]) -> Bool {
        guard !isNotStarting(units[index]), let previous = units[index - 1].scalar else { return false }
        return !notEnding.contains(previous)
    }

    private static func isNotStarting(_ unit: Unit) -> Bool {
        unit.scalar.map(notStarting.contains) ?? false
    }
}
