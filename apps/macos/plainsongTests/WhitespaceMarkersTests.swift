import Foundation
@testable import Plainsong
import Testing

@Suite
struct WhitespaceMarkersTests {
    @Test
    func findsWhitespaceByScope() {
        let paragraph = "a\u{A0}b\u{3000}\tc \u{3000}\n" as NSString
        #expect(indices(in: paragraph, scope: .all) == [1, 3, 4, 6, 7])
        #expect(indices(in: paragraph, scope: .trailing) == [6, 7])
        #expect(indices(in: paragraph, range: NSRange(location: 0, length: 3), scope: .trailing).isEmpty)
        #expect(indices(in: paragraph, scope: .selection, selectedRanges: [NSRange(location: 2, length: 3)]) == [3, 4])
        #expect(indices(in: "  ", scope: .trailing) == [0, 1])
    }

    private func indices(
        in string: NSString,
        range: NSRange? = nil,
        scope: EditorSettings.WhitespaceScope,
        selectedRanges: [NSRange] = []
    ) -> [Int] {
        WhitespaceMarkers.whitespaceIndices(
            in: string,
            range: range ?? NSRange(location: 0, length: string.length),
            scope: scope,
            selectedRanges: selectedRanges
        )
    }
}
