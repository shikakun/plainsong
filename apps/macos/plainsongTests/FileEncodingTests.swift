import Foundation
@testable import Plainsong
import Testing

@Suite
struct FileEncodingTests {
    @Test
    func keepsByteOrderMarkAndByteOrder() throws {
        let utf8 = Data([0xEF, 0xBB, 0xBF]) + Data("あ".utf8)
        let utf16 = Data([0xFE, 0xFF, 0x30, 0x42])
        for data in [utf8, utf16] {
            let (string, encoding) = try FileEncoding.decode(data)
            #expect(string == "あ")
            #expect(encoding.encode(string) == data)
        }
    }

    /// Mac OS Romanの文章は、推測するとShift_JISと判定されて化ける
    @Test
    func decodesLegacyEncodings() throws {
        let shiftJIS = try #require("日本語のテキスト".data(using: .shiftJIS))
        let (string, encoding) = try FileEncoding.decode(shiftJIS)
        #expect(string == "日本語のテキスト")
        #expect(encoding.name == "Shift-JIS")

        let macRoman = try #require(FileEncoding.encoding(fromAttribute: "MACINTOSH;0"))
        let data = try #require("Größe café".data(using: .macOSRoman))
        #expect(try FileEncoding.decode(data, attributeEncoding: macRoman).0 == "Größe café")
    }

    @Test
    func refusesUnencodableCharacters() {
        #expect(FileEncoding(encoding: .shiftJIS, hasByteOrderMark: false).encode("晴れ😀") == nil)
    }
}
