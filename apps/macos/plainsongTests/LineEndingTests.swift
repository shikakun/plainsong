@testable import Plainsong
import Testing

@Suite
struct LineEndingTests {
    @Test
    func detectsDominantLineEnding() {
        #expect(LineEnding.detect(in: "a\r\nb\r\nc\n") == (.crlf, true))
        #expect(LineEnding.detect(in: "a\rb\rc\r\n") == (.cr, true))
        #expect(LineEnding.detect(in: "a\r\nb\n") == (.lf, true))
        #expect(LineEnding.detect(in: "a\r\nb\r\n") == (.crlf, false))
    }

    @Test
    func normalizesMixedLineEndings() {
        #expect(LineEnding.crlf.normalizing("a\nb\r\nc\rd") == "a\r\nb\r\nc\r\nd")
        #expect(LineEnding.lf.normalizing("😀\r\nあ\n") == "😀\nあ\n")
    }
}
