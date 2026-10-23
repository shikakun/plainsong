import Foundation
import NaturalLanguage

enum WordCountMethod: String, CaseIterable {
    case allLanguages
    /// Microsoft Wordと同じく、日本語と中国語は1文字を1単語とする。韓国語は単語のあいだに空白を入れるので、単語のまま数える
    case japaneseAndChineseByCharacter
    case englishOnly

    private static let key = "wordCount.method"
    /// 作るたびに準備で0.2msほどかかり、打鍵のたびに数えるので使い回す
    private static let tokenizer = NLTokenizer(unit: .word)

    static func load(from defaults: UserDefaults) -> WordCountMethod {
        defaults.string(forKey: key).flatMap(WordCountMethod.init) ?? .allLanguages
    }

    func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.key)
    }

    /// 長い文字列をまとめて渡すと、途中から語を返さなくなることがあるので、段落ごとに渡す
    func count(in string: NSString, range: NSRange? = nil) -> Int {
        let range = range ?? NSRange(location: 0, length: string.length)
        let tokenizer = Self.tokenizer
        var count = 0
        string.enumerateSubstrings(in: range, options: .byParagraphs) { paragraph, _, _, _ in
            guard let paragraph else { return }
            tokenizer.string = paragraph
            tokenizer.enumerateTokens(in: paragraph.startIndex ..< paragraph.endIndex) { tokenRange, _ in
                let word = paragraph[tokenRange]
                switch self {
                case .allLanguages:
                    count += 1
                case .japaneseAndChineseByCharacter:
                    count += word.unicodeScalars.contains(where: Self.isHanOrKana) ? word.count : 1
                case .englishOnly:
                    count += word.unicodeScalars.contains(where: Self.isLatinLetter) ? 1 : 0
                }
                return true
            }
        }
        return count
    }

    private static func isHanOrKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005 ... 0x3007, // 々〆〇
             0x3040 ... 0x30FF, // ひらがな、カタカナ
             0x31F0 ... 0x31FF, // カタカナの小書き
             0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF, 0x20000 ... 0x3FFFF, // 漢字
             0xFF66 ... 0xFF9F: // 半角カタカナ
            true
        default:
            false
        }
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41 ... 0x5A, 0x61 ... 0x7A, 0xFF21 ... 0xFF3A, 0xFF41 ... 0xFF5A: // 半角と全角の英字
            true
        case 0xC0 ... 0x24F, 0x1E00 ... 0x1EFF: // アクセント記号の付いた文字などのラテン文字
            scalar.properties.isAlphabetic
        default:
            false
        }
    }
}
