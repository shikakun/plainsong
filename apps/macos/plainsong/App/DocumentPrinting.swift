import AppKit

private enum PrintedGuideLine {
    /// 線の座標の端数が線ごとに違うと、ビューアが画素に合わせるときに太さがばらついて見えるので、0.5pt単位に揃える
    static func snapped(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded(.down) / 2
    }

    /// 画面の線の濃さ（文字色の18%）を白い紙の上で再現する
    static func strokePath(in context: CGContext) {
        context.setStrokeColor(NSColor(white: 0.82, alpha: 1).cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
    }
}

private struct ManuscriptPageGeometry {
    private static let columns = ManuscriptPaper.linesPerPage
    private static let fontRatio: CGFloat = 0.72
    private static let pitchRatio: CGFloat = 1.4

    let cell: CGFloat
    let lineStart: CGFloat
    private let columnStart: CGFloat
    private let pitch: CGFloat

    var fontSize: CGFloat {
        cell * Self.fontRatio
    }

    init(lineLength: CGFloat, crossLength: CGFloat) {
        let columns = CGFloat(Self.columns)
        // ぶら下げる句読点の分を、行の方向に1マス空ける
        let cellsPerLine = CGFloat(ManuscriptPaper.standardCellsPerLine + 1)
        cell = PrintedGuideLine.snapped(min(lineLength / cellsPerLine, crossLength / (columns * Self.pitchRatio)))
        pitch = PrintedGuideLine.snapped(cell * Self.pitchRatio)
        lineStart = PrintedGuideLine.snapped((lineLength - cellsPerLine * cell) / 2)
        columnStart = PrintedGuideLine.snapped((crossLength - columns * pitch) / 2)
    }

    func middle(ofColumn column: Int) -> CGFloat {
        columnStart + (CGFloat(column) + 0.5) * pitch
    }

    /// 線を別々に引くと角が欠けるので、列の外枠を閉じた長方形にする
    func drawGrid(in context: CGContext) {
        let half = cell / 2
        for column in 0 ..< Self.columns {
            let middle = middle(ofColumn: column)
            context.addRect(CGRect(
                x: lineStart,
                y: middle - half,
                width: CGFloat(ManuscriptPaper.standardCellsPerLine) * cell,
                height: cell
            ))
            for index in 1 ..< ManuscriptPaper.standardCellsPerLine {
                let position = lineStart + CGFloat(index) * cell
                context.move(to: CGPoint(x: position, y: middle - half))
                context.addLine(to: CGPoint(x: position, y: middle + half))
            }
        }
        PrintedGuideLine.strokePath(in: context)
    }
}

/// 画面のビューを印刷すると、ウィンドウの幅で組まれ、テーマの色や行番号まで写るので、本文だけを用紙に合わせて組み直す
final class DocumentPrintView: NSView {
    private struct PlacedLine {
        var line: NSTextLineFragment
        var fragmentOrigin: CGPoint
        var paragraph: NSAttributedString
    }

    /// 段落の途中でページを切るので、段落ではなく行を単位に描く。段落を切り抜いて描くと、切り抜いた外の文字もPDFに残り、検索やコピーで重複する
    private struct Page {
        var start: CGFloat
        var lines: [PlacedLine]
    }

    private let textView: NSTextView
    private let layoutManager: LineHeightSegmentLayoutManager
    /// レイアウトマネージャーはデリゲートを弱参照で持つので、ここで持っておく
    private let fragments = WhitespaceMarkers()
    private let settings: EditorSettings
    private let text: String
    private var pageSize = NSSize.zero
    private var pages: [Page] = []
    private var manuscriptGeometry: ManuscriptPageGeometry?
    private var manuscriptPages: [[[ManuscriptPaper.Placement]]] = []
    private var japaneseMiddle: CGFloat = 0

    var showsPageNumbers: Bool
    var showsGuide = true

    var guideOptionTitle: String? {
        switch settings.guide {
        case .blank: nil
        case .ruledLines: String(localized: "print.showsRuledLines")
        case .manuscriptPaper: String(localized: "print.showsManuscriptGrid")
        }
    }

    private var isVertical: Bool {
        settings.orientation == .vertical
    }

    private var pageCount: Int {
        manuscriptGeometry == nil ? pages.count : manuscriptPages.count
    }

    override var isFlipped: Bool {
        true
    }

    private init(text: String, settings: EditorSettings) {
        let (textView, layoutManager) = EditorWindowController.makeTextView()
        self.textView = textView
        self.layoutManager = layoutManager
        self.settings = settings
        self.text = text
        showsPageNumbers = settings.showsManuscriptGuide
        super.init(frame: .zero)

        layoutManager.delegate = fragments
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.setLayoutOrientation(settings.orientation.layoutOrientation)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    static func operation(text: String, settings: EditorSettings, printInfo: NSPrintInfo) -> NSPrintOperation {
        printInfo.orientation = settings.orientation == .vertical ? .landscape : .portrait
        let view = DocumentPrintView(text: text, settings: settings)
        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.printPanel.options = [
            .showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation, .showsScaling, .showsPreview,
        ]
        operation.printPanel.addAccessoryController(PrintOptionsController(view: view))
        return operation
    }

    /// プリントパネルで用紙を変えるたびに呼ばれる
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        guard let info = NSPrintOperation.current?.printInfo else { return false }
        let size = NSSize(
            width: (info.paperSize.width - info.leftMargin - info.rightMargin) / info.scalingFactor,
            height: (info.paperSize.height - info.topMargin - info.bottomMargin) / info.scalingFactor
        )
        if size != pageSize || pageCount == 0 {
            pageSize = size
            typeset()
            setFrameSize(NSSize(width: size.width, height: size.height * CGFloat(pageCount)))
        }
        range.pointee = NSRange(location: 1, length: pageCount)
        return true
    }

    private func typeset() {
        if settings.showsManuscriptGuide {
            typesetManuscript()
        } else {
            typesetDocument()
        }
    }

    private func setBodyText(font: NSFont, paragraphStyle: NSParagraphStyle) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black,
        ]))
    }

    private func typesetDocument() {
        layoutManager.usesFontLeading = !isVertical
        let font = settings.fontFamily.font(ofSize: settings.fontSize)
        let lineHeight = EditorWindowController.lineHeight(of: settings)
        let japanese = EditorSettings.japaneseFont(for: font)
        layoutManager.lineHeight = lineHeight
        layoutManager.japaneseMiddle = (japanese.ascender + japanese.descender) / 2
        setBodyText(font: font, paragraphStyle: settings.paragraphStyle(lineHeight: lineHeight))
        JapaneseTypesetter(textView: textView).update(usesKerning: settings.usesKerning, isVertical: isVertical)

        let lineLength = isVertical ? pageSize.height : pageSize.width
        let pageExtent = isVertical ? pageSize.width : pageSize.height
        textView.textContainer?.size = NSSize(width: lineLength, height: CGFloat.greatestFiniteMagnitude)

        var page = Page(start: 0, lines: [])
        var pages: [Page] = []
        for placed in placedLines() {
            let bounds = placed.line.typographicBounds.offsetBy(
                dx: placed.fragmentOrigin.x,
                dy: placed.fragmentOrigin.y
            )
            if bounds.maxY - page.start > pageExtent, !page.lines.isEmpty {
                pages.append(page)
                page = Page(start: bounds.minY, lines: [])
            }
            page.lines.append(placed)
        }
        pages.append(page)
        self.pages = pages
    }

    /// 文字をマスより小さく置くために字間を指定すると、フォントの文字ペアの詰めが効いてマスからずれるので、TextKitでは組まず1字ずつ置く
    private func typesetManuscript() {
        let geometry = ManuscriptPageGeometry(
            lineLength: isVertical ? pageSize.height : pageSize.width,
            crossLength: isVertical ? pageSize.width : pageSize.height
        )
        manuscriptGeometry = geometry
        let font = EditorSettings.japaneseFont(for: settings.fontFamily.font(ofSize: geometry.fontSize))
        japaneseMiddle = (font.ascender + font.descender) / 2
        setBodyText(font: font, paragraphStyle: .default)
        JapaneseTypesetter(textView: textView).update(
            usesKerning: false,
            isVertical: isVertical,
            manuscriptFont: font,
            fixesCellAdvance: false
        )

        let lines = settings.manuscriptPaper.placements(in: text as NSString)
        manuscriptPages = stride(from: 0, to: max(lines.count, 1), by: ManuscriptPaper.linesPerPage).map { start in
            Array(lines[start ..< min(start + ManuscriptPaper.linesPerPage, lines.count)])
        }
    }

    private func placedLines() -> [PlacedLine] {
        var lines: [PlacedLine] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let paragraph = (fragment.textElement as? NSTextParagraph)?.attributedString else { return true }
            let origin = fragment.layoutFragmentFrame.origin
            // 末尾の改行のあとの空の行だけのページを作らない
            lines += fragment.textLineFragments.filter { $0.characterRange.length > 0 }.map {
                PlacedLine(line: $0, fragmentOrigin: origin, paragraph: paragraph)
            }
            return true
        }
        return lines
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * pageSize.height, width: pageSize.width, height: pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for index in 0 ..< pageCount where rectForPage(index + 1).intersects(dirtyRect) {
            context.saveGState()
            context.translateBy(x: 0, y: rectForPage(index + 1).minY)
            if isVertical {
                // 組むときの下が列の左、右が文字の進む下になる
                context.translateBy(x: pageSize.width, y: 0)
                context.rotate(by: .pi / 2)
            }
            if let manuscriptGeometry {
                drawManuscriptPage(manuscriptPages[index], geometry: manuscriptGeometry, in: context)
            } else {
                drawDocumentPage(pages[index], in: context)
            }
            context.restoreGState()
        }
    }

    private func drawRuledLines(on page: Page, in context: CGContext) {
        var middles = page.lines.map { placed in
            layoutManager.textMiddle(
                of: placed.line,
                in: placed.line.typographicBounds.offsetBy(dx: placed.fragmentOrigin.x, dy: placed.fragmentOrigin.y)
            ) - page.start
        }
        if middles.isEmpty, let first = layoutManager.firstLineMiddle {
            middles = [first]
        }
        let positions = RuledLines.positions(
            betweenLinesAt: middles,
            pitch: EditorWindowController.lineHeight(of: settings) * settings.lineSpacing.multiplier,
            continues: true,
            in: 0 ... (isVertical ? pageSize.width : pageSize.height)
        )
        let lineLength = isVertical ? pageSize.height : pageSize.width
        for position in positions {
            let edge = PrintedGuideLine.snapped(position)
            context.move(to: CGPoint(x: 0, y: edge))
            context.addLine(to: CGPoint(x: lineLength, y: edge))
        }
        PrintedGuideLine.strokePath(in: context)
    }

    private func drawDocumentPage(_ page: Page, in context: CGContext) {
        if settings.guide == .ruledLines, showsGuide {
            drawRuledLines(on: page, in: context)
        }
        for placed in page.lines {
            draw(
                placed,
                at: CGPoint(x: placed.fragmentOrigin.x, y: placed.fragmentOrigin.y - page.start),
                in: context
            )
        }
    }

    private func drawManuscriptPage(
        _ lines: [[ManuscriptPaper.Placement]],
        geometry: ManuscriptPageGeometry,
        in context: CGContext
    ) {
        if showsGuide {
            geometry.drawGrid(in: context)
        }
        for (column, line) in lines.enumerated() {
            for placement in line {
                let center = CGPoint(
                    x: geometry.lineStart + (CGFloat(placement.cell) + 0.5) * geometry.cell,
                    y: geometry.middle(ofColumn: column)
                )
                drawCharacter(in: placement.range, centeredAt: center, in: context)
            }
        }
    }

    private func drawCharacter(in range: NSRange, centeredAt center: CGPoint, in context: CGContext) {
        guard let storage = textView.textStorage else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        context.translateBy(x: center.x, y: center.y)
        let character = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let kind = storage.attribute(.uprightGlyphs, at: range.location, effectiveRange: nil) as? Int
        if kind == UprightGlyphs.Kind.tateChuYoko.rawValue {
            context.rotate(by: -.pi / 2)
            UprightGlyphs.drawCentered(character, in: context)
            return
        }
        if isVertical {
            character.addAttribute(
                .verticalGlyphForm,
                value: 1,
                range: NSRange(location: 0, length: character.length)
            )
        }
        let line = CTLineCreateWithAttributedString(character)
        // 縦書きではベースラインが列の中心を通り、横書きでは和文の字面の中心がその上にくる
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(
            x: -CTLineGetTypographicBounds(line, nil, nil, nil) / 2,
            y: isVertical ? 0 : -japaneseMiddle
        )
        CTLineDraw(line, context)
    }

    private func draw(_ placed: PlacedLine, at point: CGPoint, in context: CGContext) {
        UprightGlyphs.draw([placed.line], of: placed.paragraph, at: point, in: context, drawsOnlyDigits: true) {
            let origin = placed.line.typographicBounds.origin
            placed.line.draw(at: CGPoint(x: point.x + origin.x, y: point.y + origin.y), in: context)
        }
    }

    /// ページ番号は本文の外に置くので、ページの余白を含めて描けるここで描く
    override func drawPageBorder(with borderSize: NSSize) {
        guard showsPageNumbers, let operation = NSPrintOperation.current else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.black,
        ]
        let number = String(operation.currentPage) as NSString
        let size = number.size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        number.draw(
            at: NSPoint(
                x: (borderSize.width - size.width) / 2,
                y: operation.printInfo.bottomMargin / 2 - size.height / 2
            ),
            withAttributes: attributes
        )
    }
}

private final class PrintOptionsController: NSViewController, NSPrintPanelAccessorizing {
    private let printView: DocumentPrintView

    /// プリントパネルがプレビューを更新するために監視する
    @objc private dynamic var showsPageNumbers: Bool {
        didSet { printView.showsPageNumbers = showsPageNumbers }
    }

    @objc private dynamic var showsGuide: Bool {
        didSet { printView.showsGuide = showsGuide }
    }

    init(view: DocumentPrintView) {
        printView = view
        showsPageNumbers = view.showsPageNumbers
        showsGuide = view.showsGuide
        super.init(nibName: nil, bundle: nil)
        title = "Plainsong"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    private func checkbox(_ title: String, isOn: Bool, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.state = isOn ? .on : .off
        return checkbox
    }

    override func loadView() {
        var checkboxes = [checkbox(
            String(localized: "print.showsPageNumbers"),
            isOn: showsPageNumbers,
            action: #selector(changeShowsPageNumbers(_:))
        )]
        if let title = printView.guideOptionTitle {
            checkboxes.insert(checkbox(title, isOn: showsGuide, action: #selector(changeShowsGuide(_:))), at: 0)
        }
        let stack = NSStackView(views: checkboxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        // プリントパネルはAuto Layoutではなくframeで大きさを決める
        stack.frame.size = stack.fittingSize
        view = stack
    }

    @objc private func changeShowsPageNumbers(_ sender: NSButton) {
        showsPageNumbers = sender.state == .on
    }

    @objc private func changeShowsGuide(_ sender: NSButton) {
        showsGuide = sender.state == .on
    }

    private func summary(_ title: String, isOn: Bool) -> [NSPrintPanel.AccessorySummaryKey: String] {
        [
            .itemName: title,
            .itemDescription: isOn
                ? String(localized: "print.showsPageNumbers.on")
                : String(localized: "print.showsPageNumbers.off"),
        ]
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        let pageNumbers = summary(String(localized: "print.showsPageNumbers"), isOn: showsPageNumbers)
        guard let title = printView.guideOptionTitle else { return [pageNumbers] }
        return [summary(title, isOn: showsGuide), pageNumbers]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["showsPageNumbers", "showsGuide"]
    }
}
