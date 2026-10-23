import Foundation
@testable import Plainsong
import Testing

@Suite
struct WordCountTests {
    @Test
    func countsWordsByMethod() {
        let text = "日本人です。Hello, café!\u{3000}안녕하세요 세계\n3.50🍎" as NSString
        #expect(WordCountMethod.allLanguages.count(in: text) == 9)
        #expect(WordCountMethod.japaneseAndChineseByCharacter.count(in: text) == 11)
        #expect(WordCountMethod.englishOnly.count(in: text) == 2)
        #expect(WordCountMethod.allLanguages.count(in: text, range: NSRange(location: 6, length: 12)) == 2)
    }

    /// トークナイザーに全文をまとめて渡すと、「---」の行のあとの語を返さなくなる
    @Test
    func countsWordsAfterRuleLine() {
        #expect(WordCountMethod.allLanguages.count(in: "文です。\n| --- |\n文です。") == 4)
    }
}
