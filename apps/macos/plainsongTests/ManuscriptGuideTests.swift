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
    ].joined(separator: "\n")

    /// 絵文字は1字分よりわずかに広いので、行の字数だけを確かめる
    private static let textWithEmoji = text + "\n"
        + String(repeating: "😀", count: 4) + String(repeating: "あ", count: 16) + "いう\n"
        + String(repeating: "あ", count: 18) + "👨‍👩‍👧1️⃣いう"

    private func makeEditor(
        _ text: String = text,
        orientation: EditorSettings.Orientation,
        configure: (inout EditorSettings) -> Void = { _ in }
    ) async -> EditorWindowController {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.showsManuscriptGuide = true
        settings.usesReadableWidth = true
        settings.readableWidth = .japaneseShort
        configure(&settings)
        let editor = EditorWindowController(text: text, settings: settings)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        return editor
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

    private func gridView(of editor: EditorWindowController) -> ManuscriptGridView? {
        editor.window?.contentView?.subviews.lazy.compactMap { $0 as? ManuscriptGridView }.first
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], [false, true])
    func breaksLinesWhereThePaperSays(orientation: EditorSettings.Orientation, indents: Bool) async {
        let editor = await makeEditor(Self.textWithEmoji, orientation: orientation) {
            $0.indentsParagraphs = indents
        }
        let paper = ManuscriptPaper(indent: indents ? 1 : 0)
        #expect(lines(of: editor).map(\.line.characterRange.length)
            == paper.lines(in: Self.textWithEmoji as NSString).map(\.length))
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], EditorSettings.FontFamily.allCases)
    func placesEveryCharacterOnACell(
        orientation: EditorSettings.Orientation,
        fontFamily: EditorSettings.FontFamily
    ) async {
        let editor = await makeEditor(orientation: orientation) { $0.fontFamily = fontFamily }
        let cell = EditorSettings().fontSize
        for (line, origin) in lines(of: editor) {
            let characters = line.attributedString.attributedSubstring(from: line.characterRange).string
            var offset = line.characterRange.location
            var previous: Character?
            for character in characters {
                defer {
                    offset += character.utf16.count
                    previous = character
                }
                // 2桁の数字の2字目は、1字目と同じマスに入る
                guard !(character.isNumber && previous?.isNumber == true) else { continue }
                let position = origin.x + line.typographicBounds.minX + line.locationForCharacter(at: offset).x
                let remainder = position.truncatingRemainder(dividingBy: cell)
                #expect(min(remainder, cell - remainder) < 0.01, "\(character) in \(characters)")
            }
        }
    }

    /// 空行を含むどの行も、マス目の行の中心にくる
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], EditorSettings.FontFamily.allCases)
    func keepsLinesOnTheGrid(
        orientation: EditorSettings.Orientation,
        fontFamily: EditorSettings.FontFamily
    ) async throws {
        let editor = await makeEditor("\n" + Self.text + "\n\n\n" + Self.text, orientation: orientation) {
            $0.fontFamily = fontFamily
        }
        let grid = try #require(gridView(of: editor))
        let layoutManager = try #require(editor.textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        var offset = 0
        for (index, entry) in lines(of: editor).enumerated() {
            defer { offset += entry.line.characterRange.length }
            let start = contentManager.documentRange.location
            let location = try #require(contentManager.location(start, offsetBy: offset))
            let range = try #require(NSTextRange(location: location, end: location))
            var middle: CGFloat?
            layoutManager.enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
                middle = frame.midY
                return false
            }
            let actual = try #require(middle) + editor.textView.textContainerOrigin.y
            let expected = try #require(grid.middle(ofLine: index))
            #expect(abs(actual - expected) < 0.5, "line \(index)")
        }
    }

    @Test
    func restoresOrdinaryTypesettingWhenTurnedOff() async throws {
        let editor = await makeEditor(orientation: .vertical)
        var settings = EditorSettings()
        settings.orientation = .vertical
        editor.apply(settings)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(gridView(of: editor) == nil)
        let storage = try #require(editor.textStorage)
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byWordWrapping)
        let location = storage.mutableString.range(of: "2026").location
        #expect(storage.attribute(.uprightGlyphs, at: location, effectiveRange: nil) == nil)
        let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        #expect(font == settings.fontFamily.font(ofSize: settings.fontSize))
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
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], [false, true])
    func fitsCellsToTheWindow(orientation: EditorSettings.Orientation, usesReadableWidth: Bool) async throws {
        let editor = await makeEditor(String(repeating: "あ", count: 200), orientation: orientation) {
            $0.usesReadableWidth = usesReadableWidth
            $0.readableWidth = .japanese
        }
        try await resize(editor, length: 1000, orientation: orientation)
        let wide = try #require(firstLineLength(of: editor))
        if usesReadableWidth {
            #expect(wide == 40)
        }
        #expect(gridView(of: editor)?.cellsPerLine == wide)

        try await resize(editor, length: 400, orientation: orientation)
        let narrow = try #require(firstLineLength(of: editor))
        #expect(narrow < wide)
        #expect(gridView(of: editor)?.cellsPerLine == narrow)
    }
}
