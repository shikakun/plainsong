import AppKit

enum RuledLines {
    /// 1行目の前には引かない
    static func positions(
        betweenLinesAt middles: [CGFloat],
        pitch: CGFloat,
        continues: Bool,
        in range: ClosedRange<CGFloat>
    ) -> [CGFloat] {
        var rules = zip(middles, middles.dropFirst()).map { ($0 + $1) / 2 }
        if continues, pitch > 0, let last = middles.last {
            var position = last + pitch / 2
            while position <= range.upperBound {
                rules.append(position)
                position += pitch
            }
        }
        return rules.filter(range.contains)
    }
}

/// 原稿用紙と違い、行の位置はフォントや推定のレイアウトで動くので、見えている行を読んで描く
final class RuledLinesView: GuideLineView {
    var linePitch: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override init(textView: NSTextView) {
        super.init(textView: textView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(redraw(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    func rulePositions(in range: ClosedRange<CGFloat>) -> [CGFloat] {
        guard linePitch > 0 else { return [] }
        var (middles, reachesEnd) = lineMiddles(in: range)
        if middles.isEmpty, let first = firstLineMiddle {
            middles = [first]
        }
        return RuledLines.positions(betweenLinesAt: middles, pitch: linePitch, continues: reachesEnd, in: range)
    }

    /// 端にかかる罫線の位置を求めるため、範囲の前後の行まで読む
    private func lineMiddles(in range: ClosedRange<CGFloat>) -> (middles: [CGFloat], reachesEnd: Bool) {
        guard let layoutManager = textView.textLayoutManager as? LineHeightSegmentLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return ([], false) }
        let origin = textView.textContainerOrigin
        let start = layoutManager.textLayoutFragment(for: CGPoint(
            x: 0,
            y: range.lowerBound - linePitch - origin.y
        ))?.rangeInElement.location
            ?? layoutManager.textViewportLayoutController.viewportRange?.location
            ?? contentManager.documentRange.location
        var middles: [CGFloat] = []
        var reachesEnd = true
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            for line in fragment.textLineFragments {
                middles.append(layoutManager.textMiddle(
                    of: line,
                    in: line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                ))
            }
            reachesEnd = frame.maxY <= range.upperBound + linePitch
            return reachesEnd
        }
        return (middles, reachesEnd)
    }

    override func draw(_: NSRect) {
        let visible = convert(bounds, to: textView)
        let start = textView.textContainerOrigin.x
        let end = start + (textView.textContainer?.size.width ?? 0)
        let path = NSBezierPath()
        for position in rulePositions(in: visible.minY ... visible.maxY) {
            path.move(to: snapped(start, position))
            path.line(to: snapped(end, position))
        }
        stroke(path)
    }
}

extension EditorWindowController {
    func applyRuledLines(of settings: EditorSettings) {
        guard settings.guide == .ruledLines else {
            ruledLinesView?.removeFromSuperview()
            ruledLinesView = nil
            return
        }
        let view = ruledLinesView ?? RuledLinesView(textView: textView)
        if ruledLinesView == nil {
            addGuideView(view)
            ruledLinesView = view
        }
        view.color = theme?.foreground ?? .labelColor
        view.linePitch = Self.lineHeight(of: settings) * settings.lineSpacing.multiplier
    }
}
