import AppKit
@testable import Plainsong
import Testing

@Suite
struct UprightGlyphsTests {
    private func runs(_ text: String) -> [String] {
        let string = text as NSString
        return UprightGlyphs.runs(in: string, range: NSRange(location: 0, length: string.length)).map { run in
            string.substring(with: run.range) + (run.kind == .tateChuYoko ? "（縦中横）" : "")
        }
    }

    @Test
    func decidesRunsByToken() {
        #expect(runs("11月3日、GNPとMP3とA4とa") == ["11（縦中横）", "3", "GNP", "MP3", "A4", "a"])
        // 小文字を含む英単語、3桁以上の数字、記号を含むまとまりは横倒しのまま
        #expect(runs("iPhoneと2026年と3.14と10%と11/3と!").isEmpty)
    }

    /// 送りが1文字分になるので、カーソルや選択範囲も升目に沿う
    @Test
    func replacesFontsWithSquareAdvances() {
        for font in [
            EditorSettings.FontFamily.sansSerif.font(ofSize: 18),
            EditorSettings.FontFamily.serif.font(ofSize: 18),
            EditorSettings.FontFamily.sansSerif.boldFont(ofSize: 18),
        ] {
            func width(_ text: String, _ kind: UprightGlyphs.Kind) -> CGFloat {
                let replacement = UprightGlyphs.font(for: kind, replacing: font)
                #expect(UprightGlyphs.isReplacement(replacement))
                return text.size(withAttributes: [.font: replacement, .kern: 0]).width
            }
            for character in ["A", "I", "W", "3", "a"] {
                #expect(abs(width(character, .upright) - 18) < 0.01)
            }
            #expect(abs(width("12", .tateChuYoko) - 18) < 0.01)
            #expect(!UprightGlyphs.isReplacement(font))
        }
    }

    @Test
    func findsStopsWidenedInVertical() {
        let string = "あ、い。「う」、え。」お，A．" as NSString
        let indices = JapaneseTypesetter.widenedStops(in: string, range: NSRange(location: 0, length: string.length))
        // 終わり括弧が続く句読点と、末尾の句読点は除く
        #expect(indices.map { string.substring(with: NSRange(location: $0, length: 2)) } == ["、い", "。「", "、え", "，A"])
    }
}
