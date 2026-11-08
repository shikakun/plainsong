import AppKit
@testable import Plainsong
import Testing

@Suite
struct ManuscriptGuideTests {
    private static let text = [
        String(repeating: "あ", count: 20) + "。いう",
        String(repeating: "あ", count: 20) + "」。いう",
        String(repeating: "あ", count: 19) + "「いう」",
        String(repeating: "𠮷", count: 25),
        String(repeating: "あ", count: 19) + "か\u{309A}か\u{309A}か\u{309A}",
        String(repeating: "あ", count: 19) + "12あ" + String(repeating: "あ", count: 20) + "2026",
        String(repeating: "あ", count: 15) + "Supercalifragilistic。いう",
        String(repeating: "あ", count: 20) + "——" + String(repeating: "あ", count: 19) + "……",
        "“引用”と‘引用’とｱ、A B。",
        "あ\tい\t" + String(repeating: "あ", count: 17) + "\tう",
        "",
        "# 見出し **強調** `コード`",
        "「" + String(repeating: "あ", count: 30),
        String(repeating: "😀", count: 5) + String(repeating: "あ", count: 15) + "いう",
        String(repeating: "あ", count: 18) + "👨‍👩‍👧1️⃣いう",
        "éあ☺あ한あe\u{0301}あx\u{0301}あ" + String(repeating: "あ", count: 10) + "いう",
        // 行のベースラインは行頭の字のフォントで決まる
        "한あ",
        String(repeating: "ｶﾞ", count: 19) + "12ﾊﾟいう",
        "かﾞ" + String(repeating: "あ", count: 19) + "いう",
        String(repeating: "あ", count: 10) + "\u{200B}" + String(repeating: "あ", count: 10) + "いう",
    ].joined(separator: "\n")

    private func makeEditor(
        _ text: String = text,
        orientation: EditorSettings.Orientation,
        configure: (inout EditorSettings) -> Void = { _ in }
    ) async -> EditorWindowController {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.guide = .manuscriptPaper
        settings.usesReadableWidth = true
        settings.readableWidth = .japaneseShort
        configure(&settings)
        let editor = EditorWindowController(text: text, settings: settings)
        await waitForTypesetting()
        return editor
    }

    private func waitForTypesetting() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

    private func lines(of editor: EditorWindowController) -> [(line: NSTextLineFragment, origin: CGPoint)] {
        var lines: [(line: NSTextLineFragment, origin: CGPoint)] = []
        let layoutManager = editor.textView.textLayoutManager
        layoutManager?.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            lines += fragment.textLineFragments.map { ($0, fragment.layoutFragmentFrame.origin) }
            return true
        }
        return lines
    }

    /// 1字分に差し替えた字が、組んだときにも1字分の字送りになっているか
    private func fillsOneCell(_ range: NSRange, of paragraph: NSAttributedString, cell: CGFloat) -> Bool {
        guard paragraph.attribute(.uprightGlyphs, at: range.location, effectiveRange: nil) as? Int
            == UprightGlyphs.Kind.upright.rawValue
        else { return true }
        let line = CTLineCreateWithAttributedString(paragraph.attributedSubstring(from: range))
        return abs(CTLineGetTypographicBounds(line, nil, nil, nil) - cell) < 0.01
    }

    private func gridView(of editor: EditorWindowController) -> ManuscriptGridView? {
        editor.window?.contentView?.subviews.lazy.compactMap { $0 as? ManuscriptGridView }.first
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], [false, true])
    func breaksLinesWhereThePaperSays(orientation: EditorSettings.Orientation, indents: Bool) async {
        let editor = await makeEditor(orientation: orientation) {
            $0.indentsParagraphs = indents
            // 標準の字下げの幅はアプリの言語で変わるので、全角1字に決める
            $0.paragraphIndent = .fullWidth
        }
        let paper = ManuscriptPaper(indent: indents ? 1 : 0)
        #expect(lines(of: editor).map(\.line.characterRange.length)
            == paper.lines(in: Self.text as NSString).map(\.length))
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], EditorSettings.FontFamily.allCases)
    func keepsEveryCharacterOnTheGrid(
        orientation: EditorSettings.Orientation,
        fontFamily: EditorSettings.FontFamily
    ) async throws {
        for fontSize in EditorSettings.fontSizes {
            let editor = await makeEditor("\n" + Self.text + "\n\n\n" + Self.text, orientation: orientation) {
                $0.fontFamily = fontFamily
                $0.fontSize = fontSize
            }
            let grid = try #require(gridView(of: editor))
            let layoutManager = editor.layoutManager
            let isVertical = orientation == .vertical
            for (index, (line, origin)) in lines(of: editor).enumerated() {
                let characters = line.attributedString.attributedSubstring(from: line.characterRange).string
                let middle = layoutManager.verticalMiddle(
                    of: line,
                    in: line.typographicBounds,
                    isEmpty: characters.allSatisfy(\.isNewline)
                ) - (isVertical ? 0 : layoutManager.japaneseMiddle)
                let actual = origin.y + middle + editor.textView.textContainerOrigin.y
                let expected = try #require(grid.middle(ofLine: index))
                // 行送りが半端な値のとき、TextKitは行の位置を整数に丸める。行頭の絵文字は小さいフォントなので、さらに動く
                let startsWithEmoji = characters.unicodeScalars.first?.properties.isEmojiPresentation == true
                let tolerance: CGFloat = startsWithEmoji ? 2 : 1
                #expect(abs(actual - expected) <= tolerance, "\(fontSize)pt line \(index): \(characters)")

                var offset = line.characterRange.location
                var previous: Character?
                var followsUnfixedAdvance = false
                for character in characters {
                    let range = NSRange(location: offset, length: character.utf16.count)
                    defer {
                        followsUnfixedAdvance = followsUnfixedAdvance
                            || !fillsOneCell(range, of: line.attributedString, cell: fontSize)
                        offset += character.utf16.count
                        previous = character
                    }
                    // 2桁の数字の2字目は、1字目と同じマスに入る
                    guard !(character.isNumber && previous?.isNumber == true) else { continue }
                    let position = origin.x + line.typographicBounds.minX + line.locationForCharacter(at: offset).x
                    let remainder = position.truncatingRemainder(dividingBy: fontSize)
                    withKnownIssue(
                        "macOS 27のヒラギノ明朝は、持たない字をカスケードより先にOSのフォールバックで描くので、字送りの固定が効かない"
                    ) {
                        #expect(
                            min(remainder, fontSize - remainder) < 0.01,
                            "\(fontSize)pt \(character) in \(characters)"
                        )
                    } when: {
                        fontFamily == .serif && followsUnfixedAdvance
                    }
                }
            }
        }
    }

    @Test
    func restoresOrdinaryTypesettingWhenTurnedOff() async throws {
        let editor = await makeEditor(orientation: .vertical)
        var settings = EditorSettings()
        settings.orientation = .vertical
        editor.apply(settings)
        await waitForTypesetting()
        #expect(gridView(of: editor) == nil)
        let storage = try #require(editor.textStorage)
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byWordWrapping)
        let body = settings.fontFamily.font(ofSize: settings.fontSize)
        for replaced in ["2026", "😀", "ｶﾞ"] {
            let location = storage.mutableString.range(of: replaced).location
            #expect(storage.attribute(.uprightGlyphs, at: location, effectiveRange: nil) == nil, "\(replaced)")
            #expect(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == body, "\(replaced)")
        }
    }

    @Test
    func usesTheBodyFontForMarkdownWhenTurnedOn() async throws {
        var settings = EditorSettings()
        settings.highlightsMarkdown = true
        let editor = EditorWindowController(text: "**強調**と本文", settings: settings)
        await waitForTypesetting()
        settings.guide = .manuscriptPaper
        editor.apply(settings)
        await waitForTypesetting()
        let storage = try #require(editor.textStorage)
        let location = storage.mutableString.range(of: "強").location
        #expect(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == settings.bodyFont)
    }

    private func firstLineLength(of editor: EditorWindowController) -> Int? {
        lines(of: editor).first?.line.characterRange.length
    }

    private func resize(
        _ editor: EditorWindowController,
        length: CGFloat,
        orientation: EditorSettings.Orientation
    ) async throws {
        let window = try #require(editor.window)
        window.setContentSize(orientation == .vertical
            ? NSSize(width: 800, height: length)
            : NSSize(width: length, height: 800))
        await waitForTypesetting()
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func fitsCellsToTheWindow(orientation: EditorSettings.Orientation) async throws {
        let editor = await makeEditor(String(repeating: "あ", count: 200), orientation: orientation) {
            $0.usesReadableWidth = false
        }
        try await resize(editor, length: 1000, orientation: orientation)
        let wide = try #require(firstLineLength(of: editor))
        #expect(gridView(of: editor)?.cellsPerLine == wide)

        try await resize(editor, length: 400, orientation: orientation)
        let narrow = try #require(firstLineLength(of: editor))
        #expect(narrow < wide)
        #expect(gridView(of: editor)?.cellsPerLine == narrow)
    }
}
