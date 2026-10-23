import Foundation
@testable import Plainsong
import Testing

@Suite
struct LineNumbersTests {
    @Test
    func countsLineBreaks() {
        let string = "a\r\nb\rc\nd\u{2028}e\u{2029}f" as NSString
        #expect(LineNumberView.lineBreakCount(in: string, range: NSRange(location: 0, length: string.length)) == 5)
        // 読み込む区切りをまたいだ\r\nも1つと数える
        let long = String(repeating: "a", count: 4095) + "\r\n" as NSString
        #expect(LineNumberView.lineBreakCount(in: long, range: NSRange(location: 0, length: long.length)) == 1)
    }
}
