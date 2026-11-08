import AppKit
@testable import Plainsong
import Testing

@Suite
struct ManuscriptPaperTests {
    private func lengths(_ text: String, indent: Int = 0) -> [Int] {
        ManuscriptPaper(indent: indent).lines(in: text as NSString).map(\.length)
    }

    private func filler(_ count: Int) -> String {
        String(repeating: "あ", count: count)
    }

    @Test
    func hangsOnlyStopsThatLeaveTheNextLineValid() {
        #expect(lengths(filler(20) + "。いう") == [21, 2])
        #expect(lengths(filler(20) + "、") == [21])
        // 閉じ括弧はぶら下げず、前の字ごと送る
        #expect(lengths(filler(20) + "」いう") == [19, 4])
        // 句点をぶら下げると、閉じ括弧が行頭にくる
        #expect(lengths(filler(20) + "。」いう") == [19, 5])
        #expect(lengths(filler(19) + "」。いう") == [21, 2])
    }

    @Test
    func keepsProhibitedCharactersAwayFromLineEdges() {
        #expect(lengths(filler(19) + "「いう」") == [19, 4])
        #expect(lengths(filler(20) + "ゃいう") == [19, 4])
        // STKinsokuにない長音は行頭に置ける
        #expect(lengths(filler(20) + "ーいう") == [20, 3])
    }

    @Test
    func breaksAtFullCellsWhenNoValidBreakExists() {
        #expect(lengths(String(repeating: "」", count: 25)) == [20, 5])
    }

    @Test
    func countsCellsByGraphemeCluster() {
        #expect(lengths(String(repeating: "か\u{309A}", count: 21)) == [40, 2])
    }

    @Test
    func doesNotGiveACellToZeroWidthCharacters() {
        #expect(lengths(filler(10) + "\u{200B}" + filler(10) + "いう") == [21, 2])
    }

    /// 2026は縦中横にしないので、4マス使う
    @Test
    func putsOnlyTwoDigitTokensInOneCell() {
        #expect(lengths(filler(19) + "12あ") == [21, 1])
        #expect(lengths(filler(19) + "2026") == [20, 3])
        #expect(lengths(filler(18) + "iPhone") == [20, 4])
    }

    @Test
    func indentsOnlyTheFirstLineOfParagraphsThatStartWithText() {
        #expect(lengths(filler(25), indent: 1) == [19, 6])
        #expect(lengths("「" + filler(24), indent: 1) == [20, 5])
        #expect(lengths("　" + filler(24), indent: 1) == [20, 5])
        #expect(lengths(filler(25) + "\u{2028}" + filler(25), indent: 1) == [19, 7, 20, 5])
    }

    @Test
    func countsLinesAtEveryTerminator() {
        let paper = ManuscriptPaper()
        for (text, lines) in [
            ("", 0),
            ("あ\n\nい", 3),
            ("あ\r\nい", 2),
            ("あ\u{2028}い", 2),
            (filler(20) + "\n", 1),
        ] {
            #expect(paper.count(in: text as NSString) == lines, "\(text.debugDescription)")
        }
    }

    @Test
    func countsARangeThatStartsInsideALineTerminator() {
        let lines = ManuscriptPaper().lines(in: "あ\r\nい" as NSString, range: NSRange(location: 2, length: 2))
        #expect(lines.map(\.cells) == [0, 1])
    }

    /// 字下げとタブのマスを飛ばし、2桁の数字は1マスに入れる。タブは次の偶数のマスまで進む
    @Test
    func placesCharactersInCells() {
        let placements = ManuscriptPaper(indent: 1).placements(in: "あ\tい12う\n\nえ" as NSString)
        #expect(placements.map { $0.map(\.cell) } == [[1, 4, 5, 6], [], [1]])
        #expect(placements[0][2].range == NSRange(location: 3, length: 2))
    }

    /// 段落の途中から始まる行でも、全文から求めた行と同じマスの数になる。2026の後半の26が行頭にきても、2桁とみなさない
    @Test
    func measuresALineWithoutReadingTheWholeParagraph() {
        let string = (filler(18) + "2026" + filler(200)) as NSString
        let paper = ManuscriptPaper()
        var location = 0
        for line in paper.lines(in: string) {
            #expect(paper.cells(ofLineAt: location, in: string) == line.cells, "\(location)")
            location += line.length
        }
    }

    /// 画面のマス数を変えても400字詰めで数える。400字ちょうどの段落に1行足すと2枚になり、段落の途中からの選択はそこを行頭として数える
    @Test
    func showsPagesInStatusBar() async {
        var settings = EditorSettings()
        settings.guide = .manuscriptPaper
        settings.usesReadableWidth = true
        settings.readableWidth = .japanese
        settings.statusBarItems = settings.statusBarItems.map {
            ExtensionItem(kind: $0.kind, isEnabled: $0.kind == .manuscriptPages)
        }
        let editor = EditorWindowController(text: filler(400) + "\nあ", settings: settings)
        func shownText() async -> [String] {
            for _ in 0 ..< 10 {
                await Task.yield()
            }
            return textFields(in: editor.window?.contentView).map(\.stringValue)
        }
        let total = String(localized: "statusBar.manuscriptPages \(2)")
        #expect(await shownText().contains(total))

        editor.textView.setSelectedRange(NSRange(location: 390, length: 12))
        let selected = String(localized: "statusBar.manuscriptPages.selected \(1)")
        #expect(await shownText().contains(String(localized: "statusBar.countWithSelection \(total) \(selected)")))
    }

    private func textFields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        return (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(textFields(in:))
    }
}
