import Foundation
@testable import Plainsong
import Testing

@Suite
struct CharacterCountTests {
    /// 絵文字やCRLFを1文字として扱わないと、UTF-16やスカラーの数で数えてしまう
    @Test
    func countsVisibleCharactersAndExcludesChosenWhitespace() {
        let text = "a b\u{3000}c\td\r\ne👨‍👩‍👧 \u{301}" as NSString
        var options = CharacterCountOptions()
        #expect(options.count(in: text) == 9)

        options.includesTabs = true
        options.includesNewlines = true
        #expect(options.count(in: text) == 11)

        options.includesSpaces = false
        options.includesIdeographicSpaces = false
        #expect(options.count(in: text) == 9)
    }
}
