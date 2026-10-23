import Foundation
@testable import Plainsong
import Testing

@Suite
struct ParagraphCountsTests {
    /// \rのあとに\nを入れると、2つで1文字になる
    @Test
    func matchesFullCountAfterEditsAcrossParagraphs() {
        let options = CharacterCountOptions(includesNewlines: true)
        let string = NSMutableString(string: "ab\ncd\r")
        var counts = ParagraphCounts(string: string) { options.count(in: string, range: $0) }
        let edits: [(range: NSRange, replacement: String)] = [
            (NSRange(location: 6, length: 0), "\n"),
            (NSRange(location: 2, length: 1), ""),
            (NSRange(location: 1, length: 0), "x\ny"),
            (NSRange(location: 0, length: 9), ""),
            (NSRange(location: 0, length: 0), "e\u{301}\n"),
        ]
        for edit in edits {
            string.replaceCharacters(in: edit.range, with: edit.replacement)
            let length = (edit.replacement as NSString).length
            counts.update(
                string: string,
                editedRange: NSRange(location: edit.range.location, length: length),
                changeInLength: length - edit.range.length
            ) { options.count(in: string, range: $0) }
            #expect(counts.total == options.count(in: string), "\(string)")
        }
    }

    @Test
    func countsRangeAcrossParagraphs() {
        let options = CharacterCountOptions(includesNewlines: true)
        let string = "ab\r\ncd\nef\ng" as NSString
        let counts = ParagraphCounts(string: string) { options.count(in: string, range: $0) }
        let ranges = [NSRange(location: 1, length: 7), NSRange(location: 4, length: 3), NSRange(location: 2, length: 2)]
        for range in ranges {
            #expect(counts.count(in: range) { options.count(in: string, range: $0) }
                == options.count(in: string, range: range), "\(range)")
        }
    }
}
