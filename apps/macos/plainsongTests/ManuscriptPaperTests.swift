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
        #expect(lengths(filler(20) + "！いう") == [19, 4])
        #expect(lengths(filler(20) + "ゝいう") == [19, 4])
        // STKinsokuにない長音は行頭に置ける
        #expect(lengths(filler(20) + "ーいう") == [20, 3])
    }

    @Test
    func breaksAtFullCellsWhenNoValidBreakExists() {
        #expect(lengths(String(repeating: "」", count: 25)) == [20, 5])
    }

    /// 1マスに入る文字はUTF-16の長さによらない
    @Test
    func countsCellsByGraphemeCluster() {
        #expect(lengths(String(repeating: "𠮷", count: 21)) == [40, 2])
        #expect(lengths(String(repeating: "か\u{309A}", count: 21)) == [40, 2])
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
        #expect(lengths(filler(25), indent: 2) == [18, 7])
        #expect(lengths("「" + filler(24), indent: 1) == [20, 5])
        #expect(lengths("　" + filler(24), indent: 1) == [20, 5])
        #expect(lengths(filler(25) + "\u{2028}" + filler(25), indent: 1) == [19, 7, 20, 5])
    }

    @Test
    func countsLinesAtEveryTerminator() {
        let paper = ManuscriptPaper()
        for (text, lines) in [
            ("", 0),
            ("\n", 1),
            ("あ\n", 1),
            ("あ\n\nい", 3),
            ("あ\r\nい", 2),
            ("あ\u{2028}い", 2),
            (filler(20) + "\n", 1),
        ] {
            #expect(paper.count(in: text as NSString) == lines, "\(text.debugDescription)")
        }
    }

    @Test
    func roundsPartialPagesUp() {
        #expect(ManuscriptPaper.pages(forLines: 0) == 0)
        #expect(ManuscriptPaper.pages(forLines: 1) == 1)
        #expect(ManuscriptPaper.pages(forLines: 20) == 1)
        #expect(ManuscriptPaper.pages(forLines: 21) == 2)
    }

    /// 400字ちょうどの段落に1行足すと2枚になり、段落の途中からの選択はそこを行頭として数える
    @Test
    func showsPagesInStatusBar() async {
        var settings = EditorSettings()
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

    /// 枚数とマス目が食い違わないよう、計算した幅を渡したTextKit 2が同じ行に組むことを確かめる
    @Test
    func matchesTextKitLayoutInBothOrientations() {
        let text = [
            filler(20) + "。いう",
            filler(20) + "」。いう",
            filler(19) + "「いう」",
            String(repeating: "𠮷", count: 25),
            filler(19) + "か\u{309A}か\u{309A}か\u{309A}",
            filler(19) + "12あ" + filler(20) + "2026",
            filler(15) + "Supercalifragilistic。いう",
            filler(20) + "——" + filler(19) + "……",
            "あ\tい\t" + filler(17) + "\tう",
            "",
            "「" + filler(30),
        ].joined(separator: "\n")
        for indent in [0, 1, 2] {
            let paper = ManuscriptPaper(indent: indent)
            let expected = paper.lines(in: text as NSString)
            for orientation in [NSLayoutManager.TextLayoutOrientation.horizontal, .vertical] {
                let actual = laidOutLengths(text, paper: paper, indent: indent, orientation: orientation)
                #expect(actual == expected.map(\.length), "indent: \(indent), \(orientation)")
            }
        }
    }

    private func laidOutLengths(
        _ text: String,
        paper: ManuscriptPaper,
        indent: Int,
        orientation: NSLayoutManager.TextLayoutOrientation
    ) -> [Int] {
        let fontSize: CGFloat = 16
        let font = EditorSettings.FontFamily.sansSerif.font(ofSize: fontSize)
        let storage = NSTextContentStorage()
        storage.delegate = ParagraphIndentRules.shared
        let layoutManager = NSTextLayoutManager()
        storage.addTextLayoutManager(layoutManager)
        let container = CellWidthTextContainer(paper: paper, text: text, cellWidth: fontSize)
        layoutManager.textContainer = container
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        textView.setLayoutOrientation(orientation)

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.firstLineHeadIndent = CGFloat(indent) * fontSize
        style.tabStops = []
        style.defaultTabInterval = fontSize * EditorSettings.tabEms
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: style, .kern: 0]
        )
        applySquareAdvances(to: attributed, font: font)
        textView.textStorage?.setAttributedString(attributed)

        var lengths: [Int] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            lengths += fragment.textLineFragments.map(\.characterRange.length)
            return true
        }
        return lengths
    }

    /// 原稿用紙に組むときの、すべての文字が1マスになる字形を再現する
    private func applySquareAdvances(to text: NSMutableAttributedString, font: NSFont) {
        let string = text.string as NSString
        let tateChuYoko = UprightGlyphs.runs(in: string, range: NSRange(location: 0, length: string.length))
            .filter { $0.kind == .tateChuYoko }
            .map(\.range)
        let square = UprightGlyphs.font(for: .upright, replacing: font)
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: .byComposedCharacterSequences
        ) { substring, range, _, _ in
            guard let scalar = substring?.unicodeScalars.first,
                  scalar.isASCII || "—…".unicodeScalars.contains(scalar),
                  !scalar.properties.isWhitespace
            else { return }
            text.addAttribute(.font, value: square, range: range)
        }
        let half = UprightGlyphs.font(for: .tateChuYoko, replacing: font)
        tateChuYoko.forEach { text.addAttribute(.font, value: half, range: $0) }
    }
}

private final nonisolated class CellWidthTextContainer: NSTextContainer {
    private var cellsByLineStart: [Int: Int] = [:]
    private let cellWidth: CGFloat

    init(paper: ManuscriptPaper, text: String, cellWidth: CGFloat) {
        self.cellWidth = cellWidth
        super.init(size: NSSize(width: cellWidth * 20, height: CGFloat.greatestFiniteMagnitude))
        lineFragmentPadding = 0
        widthTracksTextView = false
        var location = 0
        for line in paper.lines(in: text as NSString) {
            cellsByLineStart[location] = line.cells
            location += line.length
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override var isSimpleRectangularTextContainer: Bool {
        false
    }

    override func lineFragmentRect(
        forProposedRect proposedRect: CGRect,
        at characterIndex: Int,
        writingDirection: NSWritingDirection,
        remaining: UnsafeMutablePointer<CGRect>?
    ) -> CGRect {
        var rect = super.lineFragmentRect(
            forProposedRect: proposedRect,
            at: characterIndex,
            writingDirection: writingDirection,
            remaining: remaining
        )
        if let cells = cellsByLineStart[characterIndex], cells > 0 {
            rect.size.width = CGFloat(cells) * cellWidth
        }
        return rect
    }
}
