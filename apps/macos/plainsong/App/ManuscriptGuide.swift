import AppKit

/// 行の字数を`ManuscriptPaper`で決めるため、行ごとに幅を渡す。TextKitは渡した幅に入るだけの文字を組む
final nonisolated class ManuscriptTextContainer: NSTextContainer {
    var paper: ManuscriptPaper?
    var cellWidth: CGFloat = 0

    override var isSimpleRectangularTextContainer: Bool {
        paper == nil && super.isSimpleRectangularTextContainer
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
        guard let paper,
              let storage = (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
        else { return rect }
        let cells = paper.cells(ofLineAt: characterIndex, in: storage.mutableString)
        if cells > 0 {
            // 絵文字は1字分よりわずかに広い。次の文字が入らない範囲で余裕を持たせ、計算どおりの字数で折り返す
            rect.size.width = (CGFloat(cells) + 0.25) * cellWidth
        }
        return rect
    }
}

/// 本文の行は一定の間隔で並ぶので、マス目は本文を見ずに描ける。文字より先に描く必要はないので、行番号と同じく本文に重ねる
final class ManuscriptGridView: NSView {
    private let textView: NSTextView

    var cellSize: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var linePitch: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var cellsPerLine = ManuscriptPaper.standardCellsPerLine {
        didSet { needsDisplay = true }
    }

    var color = NSColor.labelColor {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        if let clipView = textView.enclosingScrollView?.contentView {
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(redraw(_:)),
                    name: name,
                    object: clipView
                )
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(redraw(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    @objc private func redraw(_: Notification) {
        needsDisplay = true
    }

    /// 組むときの座標での、行の中心の位置を返す。縦書きでは右の列からの距離になる
    func middle(ofLine line: Int) -> CGFloat? {
        guard let layoutManager = textView.textLayoutManager,
              let start = layoutManager.textContentManager?.documentRange.location,
              let range = NSTextRange(location: start, end: start)
        else { return nil }
        var first: CGFloat?
        layoutManager.enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
            first = frame.midY
            return false
        }
        return first.map { $0 + textView.textContainerOrigin.y + CGFloat(line) * linePitch }
    }

    override func draw(_: NSRect) {
        guard cellSize > 0, linePitch > 0, let first = middle(ofLine: 0) else { return }
        let visible = convert(bounds, to: textView)
        let half = cellSize / 2
        let firstLine = max(Int(((visible.minY - half - first) / linePitch).rounded(.down)), 0)
        let lastLine = Int(((visible.maxY + half - first) / linePitch).rounded(.up))
        guard firstLine <= lastLine else { return }

        let scale = window?.backingScaleFactor ?? 1
        func snapped(_ position: CGFloat, _ edge: CGFloat) -> CGPoint {
            let point = convert(CGPoint(x: position, y: edge), from: textView)
            return CGPoint(
                x: ((point.x * scale).rounded(.down) + 0.5) / scale,
                y: ((point.y * scale).rounded(.down) + 0.5) / scale
            )
        }
        let path = NSBezierPath()
        let start = textView.textContainerOrigin.x
        let end = start + CGFloat(cellsPerLine) * cellSize
        for line in firstLine ... lastLine {
            let middle = first + CGFloat(line) * linePitch
            for edge in [middle - half, middle + half] {
                path.move(to: snapped(start, edge))
                path.line(to: snapped(end, edge))
            }
            for cell in 0 ... cellsPerLine {
                let position = start + CGFloat(cell) * cellSize
                path.move(to: snapped(position, middle - half))
                path.line(to: snapped(position, middle + half))
            }
        }
        path.lineWidth = 1 / scale
        lineColor.setStroke()
        path.stroke()
    }

    private var lineColor: NSColor {
        color.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.55 : 0.18)
    }
}

extension EditorWindowController {
    func applyManuscriptGrid(of settings: EditorSettings) {
        guard settings.showsManuscriptGuide else {
            manuscriptGridView?.removeFromSuperview()
            manuscriptGridView = nil
            return
        }
        let gridView = manuscriptGridView ?? ManuscriptGridView(textView: textView)
        if manuscriptGridView == nil {
            gridView.frame = container.bounds
            gridView.autoresizingMask = [.width, .height]
            container.addSubview(gridView, positioned: .above, relativeTo: scrollView)
            manuscriptGridView = gridView
        }
        gridView.color = theme?.foreground ?? .labelColor
        gridView.cellSize = settings.fontSize
        gridView.linePitch = Self.lineHeight(of: settings) * settings.lineSpacing.multiplier
    }

    /// ウィンドウの大きさを変えているあいだは何度も呼ばれるので、変わったときだけ組み直す
    func applyManuscriptCells(_ cells: Int, of settings: EditorSettings) {
        manuscriptGridView?.cellsPerLine = cells
        guard let container = textView.textContainer as? ManuscriptTextContainer else { return }
        var paper = settings.manuscriptPaper
        paper.cellsPerLine = cells
        guard paper != container.paper else { return }
        container.paper = paper
        if let documentRange = layoutManager.textContentManager?.documentRange {
            layoutManager.invalidateLayout(for: documentRange)
        }
        layoutManager.textViewportLayoutController.layoutViewport()
        redrawText()
    }
}

final class ManuscriptGuideOptions: NSObject {
    private let model: SettingsModel
    private let checkbox = NSButton(
        checkboxWithTitle: String(localized: "settings.manuscriptGuide"),
        target: nil,
        action: nil
    )

    init(model: SettingsModel) {
        self.model = model
        super.init()
        checkbox.target = self
        checkbox.action = #selector(change(_:))
    }

    func makeSection() -> NSGridView {
        SettingsPane.columns([[SettingsPane.label(String(localized: "settings.guide")), checkbox]])
    }

    func update(with settings: EditorSettings) {
        checkbox.state = settings.showsManuscriptGuide ? .on : .off
    }

    @objc private func change(_ sender: NSButton) {
        model.update { $0.showsManuscriptGuide = sender.state == .on }
    }
}
