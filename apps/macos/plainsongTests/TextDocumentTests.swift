import Foundation
@testable import Plainsong
import Testing

@Suite
struct TextDocumentTests {
    @Test
    func makesFileNameFromFirstNonEmptyLine() {
        #expect(TextDocument.fileName(for: "\n  .memo: a/b  \nnext") == "memo- a-b")
        #expect(TextDocument.fileName(for: String(repeating: "あ", count: 40)) == String(repeating: "あ", count: 30))
        #expect(TextDocument.fileName(for: " \n\n") == nil)
    }
}
