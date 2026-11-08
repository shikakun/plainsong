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
            // 丸め誤差で最後の字が次の行に送られないよう、次の字が入らない範囲で余裕を持たせる
            rect.size.width = (CGFloat(cells) + 0.25) * cellWidth
        }
        return rect
    }
}

/// 本文の行は一定の間隔で並ぶので、マス目は本文を見ずに描ける
final class ManuscriptGridView: GuideLineView {
    var cellSize: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var linePitch: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var cellsPerLine = ManuscriptPaper.standardCellsPerLine {
        didSet { needsDisplay = true }
    }

    func middle(ofLine line: Int) -> CGFloat? {
        firstLineMiddle.map { $0 + CGFloat(line) * linePitch }
    }

    override func draw(_: NSRect) {
        guard cellSize > 0, linePitch > 0, let first = middle(ofLine: 0) else { return }
        let visible = convert(bounds, to: textView)
        let half = cellSize / 2
        let firstLine = max(Int(((visible.minY - half - first) / linePitch).rounded(.down)), 0)
        let lastLine = Int(((visible.maxY + half - first) / linePitch).rounded(.up))
        guard firstLine <= lastLine else { return }

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
        stroke(path)
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
            addGuideView(gridView)
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
