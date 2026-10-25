import Foundation
@testable import Plainsong
import Testing

@Suite
struct TextSearchTests {
    private func ranges(_ search: TextSearch, in string: String) throws -> [NSRange] {
        let string = string as NSString
        return try search.matches(in: string).map(\.range)
    }

    @Test
    func findsEveryMatch() throws {
        let search = TextSearch(pattern: "雨")
        #expect(try ranges(search, in: "雨の日、雨音を聞く").map(\.location) == [0, 4])
        #expect(try ranges(TextSearch(), in: "雨") == [])
    }

    @Test
    func matchesCaseAndWidthAsOptioned() throws {
        var search = TextSearch(pattern: "abc")
        #expect(try ranges(search, in: "ABC abc").count == 2)
        search.matchesCase = true
        #expect(try ranges(search, in: "ABC abc") == [NSRange(location: 4, length: 3)])
        search.matchesWidth = false
        #expect(try ranges(search, in: "ａｂｃ abc").count == 2)
    }

    @Test
    func countsInUTF16() throws {
        #expect(try ranges(TextSearch(pattern: "雨"), in: "😀雨") == [NSRange(location: 2, length: 1)])
    }

    @Test
    func expandsRegularExpressionTemplate() throws {
        let search = TextSearch(pattern: "「(.+?)」", usesRegularExpression: true)
        let string = "「雨」と「雪」" as NSString
        let matches = try search.matches(in: string)
        #expect(matches.map { TextSearch.replacement(for: $0, in: string, template: "『$1』") } == ["『雨』", "『雪』"])
        #expect(TextSearch.replacement(for: matches[0], in: string, template: "$1") == "雨")
    }

    @Test
    func keepsLiteralTemplate() throws {
        let string = "雨" as NSString
        let matches = try TextSearch(pattern: "雨").matches(in: string)
        let match = try #require(matches.first)
        #expect(TextSearch.replacement(for: match, in: string, template: "$1") == "$1")
    }

    @Test
    func anchorsRegularExpressionToLines() throws {
        let search = TextSearch(pattern: "^", usesRegularExpression: true)
        #expect(try ranges(search, in: "あ\nい").map(\.location) == [0, 2])
    }

    @Test
    func rejectsInvalidPattern() {
        #expect(throws: TextSearch.InvalidPattern.self) {
            try ranges(TextSearch(pattern: "(", usesRegularExpression: true), in: "(")
        }
    }

    @Test
    func adjustsRangesForEdits() {
        let range = NSRange(location: 10, length: 2)
        // 手前の2文字を5文字に書き換えると、後ろにずれる
        #expect(range.adjusted(forEditIn: NSRange(location: 0, length: 5), changeInLength: 3)?.location == 13)
        #expect(range.adjusted(forEditIn: NSRange(location: 20, length: 1), changeInLength: 1) == range)
        #expect(range.adjusted(forEditIn: NSRange(location: 11, length: 1), changeInLength: 0) == nil)
    }

    @Test
    func resizesRangesForEditsInside() {
        let range = NSRange(location: 10, length: 10)
        // 範囲の中の2文字を5文字に書き換えると、3文字伸びる
        #expect(range.resized(forEditIn: NSRange(location: 12, length: 5), changeInLength: 3).length == 13)
        // 範囲の末尾をまたいで書き換えると、書き換えたあとの文字まで範囲に含める
        #expect(range.resized(forEditIn: NSRange(location: 18, length: 2), changeInLength: -5).length == 10)
    }
}
