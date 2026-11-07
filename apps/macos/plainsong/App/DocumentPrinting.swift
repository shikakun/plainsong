import AppKit

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
    private let layoutManager: NSTextLayoutManager
    /// レイアウトマネージャーはデリゲートを弱参照で持つので、ここで持っておく
    private let fragments = WhitespaceMarkers()
    private let isVertical: Bool
    private var pageSize = NSSize.zero
    private var pages: [Page] = []

    var showsPageNumbers = false

    override var isFlipped: Bool {
        true
    }

    private init(text: String, settings: EditorSettings) {
        let (textView, layoutManager) = EditorWindowController.makeTextView()
        self.textView = textView
        self.layoutManager = layoutManager
        isVertical = settings.orientation == .vertical
        super.init(frame: .zero)

        layoutManager.delegate = fragments
        layoutManager.usesFontLeading = !isVertical
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.setLayoutOrientation(settings.orientation.layoutOrientation)
        let lineHeight = EditorWindowController.lineHeight(of: settings)
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: settings.fontFamily.font(ofSize: settings.fontSize),
            .paragraphStyle: settings.paragraphStyle(lineHeight: lineHeight),
            .foregroundColor: NSColor.black,
        ]))
        JapaneseTypesetter(textView: textView).update(usesKerning: settings.usesKerning, isVertical: isVertical)
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
        if size != pageSize || pages.isEmpty {
            pageSize = size
            typeset()
            setFrameSize(NSSize(width: size.width, height: size.height * CGFloat(pages.count)))
        }
        range.pointee = NSRange(location: 1, length: pages.count)
        return true
    }

    private func typeset() {
        let lineLength = isVertical ? pageSize.height : pageSize.width
        let pageExtent = isVertical ? pageSize.width : pageSize.height
        textView.textContainer?.size = NSSize(width: lineLength, height: CGFloat.greatestFiniteMagnitude)

        var page = Page(start: 0, lines: [])
        var pages: [Page] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let paragraph = (fragment.textElement as? NSTextParagraph)?.attributedString else { return true }
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
                if bounds.maxY - page.start > pageExtent, !page.lines.isEmpty {
                    pages.append(page)
                    page = Page(start: bounds.minY, lines: [])
                }
                page.lines.append(PlacedLine(line: line, fragmentOrigin: origin, paragraph: paragraph))
            }
            return true
        }
        pages.append(page)
        self.pages = pages
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * pageSize.height, width: pageSize.width, height: pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for (index, page) in pages.enumerated() where rectForPage(index + 1).intersects(dirtyRect) {
            context.saveGState()
            context.translateBy(x: 0, y: rectForPage(index + 1).minY)
            if isVertical {
                // 組むときの下が列の左、右が文字の進む下になる
                context.translateBy(x: pageSize.width + page.start, y: 0)
                context.rotate(by: .pi / 2)
            } else {
                context.translateBy(x: 0, y: -page.start)
            }
            for placed in page.lines {
                UprightGlyphs.draw([placed.line], of: placed.paragraph, at: placed.fragmentOrigin, in: context) {
                    let origin = placed.line.typographicBounds.origin
                    placed.line.draw(
                        at: CGPoint(x: placed.fragmentOrigin.x + origin.x, y: placed.fragmentOrigin.y + origin.y),
                        in: context
                    )
                }
            }
            context.restoreGState()
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
    @objc private dynamic var showsPageNumbers = false {
        didSet { printView.showsPageNumbers = showsPageNumbers }
    }

    init(view: DocumentPrintView) {
        printView = view
        super.init(nibName: nil, bundle: nil)
        title = "Plainsong"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override func loadView() {
        let checkbox = NSButton(
            checkboxWithTitle: String(localized: "print.showsPageNumbers"),
            target: self,
            action: #selector(changeShowsPageNumbers(_:))
        )
        checkbox.state = showsPageNumbers ? .on : .off
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(checkbox)
        NSLayoutConstraint.activate([
            checkbox.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            checkbox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            checkbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            checkbox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        // プリントパネルはAuto Layoutではなくframeで大きさを決める
        container.frame.size = container.fittingSize
        view = container
    }

    @objc private func changeShowsPageNumbers(_ sender: NSButton) {
        showsPageNumbers = sender.state == .on
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[
            .itemName: String(localized: "print.showsPageNumbers"),
            .itemDescription: showsPageNumbers
                ? String(localized: "print.showsPageNumbers.on")
                : String(localized: "print.showsPageNumbers.off"),
        ]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["showsPageNumbers"]
    }
}
