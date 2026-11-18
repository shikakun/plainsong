import AppKit
@testable import Plainsong
import Testing

@Suite
struct HangingPunctuationTests {
    /// 1行は20字。1行目は1字下げるが、始め括弧で始まる段落は下げない
    private static let paragraphs: [(text: String, lines: [Int])] = [
        (String(repeating: "あ", count: 19) + "。いう", [20, 3]),
        ("「" + String(repeating: "あ", count: 19) + "。いう", [21, 3]),
        (String(repeating: "あ", count: 19) + String(repeating: "い", count: 20) + "。う", [19, 21, 2]),
        // 。のあとの」も行頭に置けないので、ぶら下げずに前の字と一緒に送る
        (String(repeating: "あ", count: 19) + "。」いう", [18, 5]),
    ]

    private func makeEditor(
        _ text: String,
        orientation: EditorSettings.Orientation,
        configure: (inout EditorSettings) -> Void = { _ in }
    ) async -> EditorWindowController {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.usesReadableWidth = true
        settings.readableWidth = .japaneseShort
        configure(&settings)
        let editor = EditorWindowController(text: text, settings: settings)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        return editor
    }

    private func lineLengths(in editor: EditorWindowController) -> [Int] {
        var lengths: [Int] = []
        editor.layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) {
            lengths += $0.textLineFragments.map(\.characterRange.length)
            return true
        }
        return lengths
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], [false, true])
    func hangsStopsPastTheLineEnd(orientation: EditorSettings.Orientation, usesKerning: Bool) async {
        let text = Self.paragraphs.map(\.text).joined(separator: "\n")
        let editor = await makeEditor(text, orientation: orientation) {
            $0.usesKerning = usesKerning
            $0.indentsParagraphs = true
            // 標準の字下げの幅はアプリの言語で変わるので、全角1字に決める
            $0.paragraphIndent = .fullWidth
        }

        #expect(lineLengths(in: editor) == Self.paragraphs.flatMap(\.lines))
    }

    @Test
    func pushesStopsOutWhenHangingIsOff() async {
        let editor = await makeEditor(String(repeating: "あ", count: 20) + "。いう", orientation: .horizontal) {
            $0.hangsPunctuation = false
        }
        #expect(lineLengths(in: editor) == [19, 4])
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func selectsTheHungStopWithoutStretchingOtherLines(orientation: EditorSettings.Orientation) async throws {
        let text = String(repeating: "あ", count: 20) + "。" + String(repeating: "い", count: 20) + "うえ"
        let editor = await makeEditor(text, orientation: orientation)
        let layoutManager = editor.layoutManager
        var first: NSTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) {
            first = $0
            return false
        }
        let fragment = try #require(first)
        let line = try #require(fragment.textLineFragments.first)
        #expect(line.characterRange.length == 21)
        let stopEnd = fragment.layoutFragmentFrame.minX + line.typographicBounds.minX
            + line.locationForCharacter(at: 21).x
        #expect(try stopEnd <= #require(editor.textView.textContainer).size.width)

        let content = try #require(layoutManager.textContentManager)
        let start = try #require(content.location(content.documentRange.location, offsetBy: 19))
        let end = try #require(content.location(start, offsetBy: 24))
        var bands: [CGRect] = []
        try layoutManager.enumerateTextSegments(
            in: #require(NSTextRange(location: start, end: end)),
            type: .selection,
            options: .rangeNotRequired
        ) { _, frame, _, _ in
            bands.append(frame)
            return true
        }
        try #require(bands.count == 3)
        #expect(bands[0].maxX == stopEnd)
        #expect(bands[1].maxX < stopEnd)
        let secondLine = fragment.textLineFragments[1]
        let secondEnd = fragment.layoutFragmentFrame.minX + secondLine.typographicBounds.minX
            + secondLine.locationForCharacter(at: 41).x
        #expect(secondEnd <= bands[1].maxX)
    }
}
