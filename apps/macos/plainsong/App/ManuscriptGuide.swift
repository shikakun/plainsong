import AppKit

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
        guard let container = textView.textContainer as? EditorTextContainer else { return }
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
