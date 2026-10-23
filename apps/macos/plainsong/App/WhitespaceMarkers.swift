import AppKit

final nonisolated class WhitespaceMarkers: NSObject, NSTextLayoutManagerDelegate {
    var scope: EditorSettings.WhitespaceScope?
    var showsNewlines = false
    var color = NSColor.tertiaryLabelColor
    /// 「選択範囲のみ」で使う、本文の先頭からの範囲
    var selectedRanges: [NSRange] = []

    func textLayoutManager(
        _: NSTextLayoutManager,
        textLayoutFragmentFor _: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        WhitespaceLayoutFragment(textElement: textElement, range: textElement.elementRange, markers: self)
    }

    /// rangeの中で記号を描く空白を探し、string（段落）の中での位置を返す。selectedRangesもstringの中の範囲で渡す
    /// ここでの行末は改行の直前か段落の末尾で、折り返した位置は行末としない
    static func whitespaceIndices(
        in string: NSString,
        range: NSRange,
        scope: EditorSettings.WhitespaceScope,
        selectedRanges: [NSRange] = []
    ) -> [Int] {
        let end = lineBreakStart(in: string) ?? string.length
        var start = range.location
        if case .trailing = scope {
            var trailingStart = end
            while trailingStart > 0, isWhitespace(string.character(at: trailingStart - 1)) {
                trailingStart -= 1
            }
            start = max(start, trailingStart)
        }
        let upperBound = min(NSMaxRange(range), end)
        guard start < upperBound else { return [] }
        return (start ..< upperBound).filter { index in
            guard isWhitespace(string.character(at: index)) else { return false }
            guard case .selection = scope else { return true }
            return selectedRanges.contains { NSLocationInRange(index, $0) }
        }
    }

    /// \r\nは2文字で1つの改行なので、先頭の位置を返す
    static func lineBreakStart(in string: NSString) -> Int? {
        var start = string.length
        while start > 0, isNewline(string.character(at: start - 1)) {
            start -= 1
        }
        return start < string.length ? start : nil
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        switch character {
        case 0x20, 0x3000, 0x09, 0xA0, 0x2007, 0x202F, 0x2000 ... 0x200A, 0x205F: true
        default: false
        }
    }

    private static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029
    }
}

private final nonisolated class WhitespaceLayoutFragment: NSTextLayoutFragment {
    private let markers: WhitespaceMarkers

    init(textElement: NSTextElement, range: NSTextRange?, markers: WhitespaceMarkers) {
        self.markers = markers
        super.init(textElement: textElement, range: range)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    /// 空の行は描ける範囲の幅がなく、改行の記号が切れるので、行の幅に記号1つ分を足した範囲まで広げる
    /// 描ける範囲は組むときに決まり、表示を切り替えても組み直さないので、オフのときも広げておく
    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        guard let attributedString = (textElement as? NSTextParagraph)?.attributedString,
              attributedString.length > 0,
              let font = attributedString.attribute(.font, at: attributedString.length - 1, effectiveRange: nil)
              as? NSFont
        else { return bounds }
        let frame = layoutFragmentFrame
        return bounds.union(CGRect(x: 0, y: 0, width: frame.width + font.pointSize, height: frame.height))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard markers.scope != nil || markers.showsNewlines,
              let attributedString = (textElement as? NSTextParagraph)?.attributedString
        else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        markers.color.set()
        if let scope = markers.scope {
            drawWhitespace(of: attributedString, scope: scope, at: point, clip: context.boundingBoxOfClipPath)
        }
        if markers.showsNewlines {
            drawLineBreak(of: attributedString, at: point)
        }
    }

    private func drawWhitespace(
        of attributedString: NSAttributedString,
        scope: EditorSettings.WhitespaceScope,
        at point: CGPoint,
        clip: CGRect
    ) {
        let string = attributedString.string as NSString
        let selectedRanges = paragraphSelectedRanges(scope: scope)
        if case .selection = scope, selectedRanges.isEmpty {
            return
        }
        for line in textLineFragments {
            let bounds = line.typographicBounds.offsetBy(dx: point.x, dy: point.y)
            guard bounds.intersects(clip) else { continue }
            let indices = WhitespaceMarkers.whitespaceIndices(
                in: string,
                range: line.characterRange,
                scope: scope,
                selectedRanges: selectedRanges
            )
            for index in indices {
                guard let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont
                else { continue }
                let minX = bounds.minX + line.locationForCharacter(at: index).x
                let maxX = bounds.minX + line.locationForCharacter(at: index + 1).x
                let baseline = bounds.minY + line.glyphOrigin.y
                Self.drawMarker(for: string.character(at: index), from: minX, to: maxX, baseline: baseline, font: font)
            }
        }
    }

    private func drawLineBreak(of attributedString: NSAttributedString, at point: CGPoint) {
        guard let index = WhitespaceMarkers.lineBreakStart(in: attributedString.string as NSString),
              let line = textLineFragments.last(where: { $0.characterRange.location <= index }),
              let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        else { return }
        let bounds = line.typographicBounds.offsetBy(dx: point.x, dy: point.y)
        // 空の行は、行間を文字の上に分けず行の高さに含めて組むので、ベースラインを下端から求める
        let baseline = index == line.characterRange.location
            ? bounds.maxY + font.descender
            : bounds.minY + line.glyphOrigin.y
        Self.drawPilcrow(at: bounds.minX + line.locationForCharacter(at: index).x, baseline: baseline, font: font)
    }

    private func paragraphSelectedRanges(scope: EditorSettings.WhitespaceScope) -> [NSRange] {
        guard case .selection = scope,
              let contentManager = textLayoutManager?.textContentManager
        else { return [] }
        let location = contentManager.offset(from: contentManager.documentRange.location, to: rangeInElement.location)
        let length = contentManager.offset(from: rangeInElement.location, to: rangeInElement.endLocation)
        let paragraph = NSRange(location: location, length: length)
        return markers.selectedRanges.compactMap { range in
            guard let intersection = range.intersection(paragraph), intersection.length > 0 else { return nil }
            return NSRange(location: intersection.location - location, length: intersection.length)
        }
    }

    private static func drawMarker(
        for character: unichar,
        from minX: CGFloat,
        to maxX: CGFloat,
        baseline: CGFloat,
        font: NSFont
    ) {
        let size = font.pointSize
        let lineWidth = size / 16
        let width = maxX - minX
        let midX = minX + width / 2
        let midY = baseline - font.xHeight / 2
        let halfWidth = min(size / 8, width * 0.4)
        switch character {
        case 0x20, 0xA0, 0x2007, 0x202F:
            let diameter = size / 8
            NSBezierPath(ovalIn: CGRect(
                x: midX - diameter / 2,
                y: midY - diameter / 2,
                width: diameter,
                height: diameter
            )).fill()
            guard character != 0x20 else { return }
            let apex = midY - diameter * 2
            let path = NSBezierPath()
            path.move(to: CGPoint(x: midX - halfWidth, y: apex + size / 12))
            path.line(to: CGPoint(x: midX, y: apex))
            path.line(to: CGPoint(x: midX + halfWidth, y: apex + size / 12))
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case 0x3000:
            let side = width * 0.6
            let rect = CGRect(
                x: minX + (width - side) / 2,
                y: baseline - font.capHeight / 2 - side / 2,
                width: side,
                height: side
            )
            let path = NSBezierPath(rect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            path.lineWidth = lineWidth
            path.stroke()
        case 0x09:
            let head = size / 5
            let start = minX + size / 8
            let end = max(maxX - size / 8, start + head)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: start, y: midY))
            path.line(to: CGPoint(x: end, y: midY))
            path.move(to: CGPoint(x: end - head, y: midY - head))
            path.line(to: CGPoint(x: end, y: midY))
            path.line(to: CGPoint(x: end - head, y: midY + head))
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        default:
            let path = NSBezierPath()
            for lineY in [midY - size / 16, midY + size / 16] {
                path.move(to: CGPoint(x: midX - halfWidth, y: lineY))
                path.line(to: CGPoint(x: midX + halfWidth, y: lineY))
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private static func drawPilcrow(at minX: CGFloat, baseline: CGFloat, font: NSFont) {
        let size = font.pointSize
        let lineWidth = size / 16
        let top = baseline - font.capHeight
        let bowlWidth = size * 0.22
        let leftStem = minX + size / 8 + bowlWidth
        let rightStem = leftStem + size * 0.15
        let bowlRadius = font.capHeight / 4
        let curve: CGFloat = 0.5523

        let bowl = NSBezierPath()
        bowl.move(to: CGPoint(x: leftStem, y: top))
        bowl.curve(
            to: CGPoint(x: leftStem - bowlWidth, y: top + bowlRadius),
            controlPoint1: CGPoint(x: leftStem - bowlWidth * curve, y: top),
            controlPoint2: CGPoint(x: leftStem - bowlWidth, y: top + bowlRadius * (1 - curve))
        )
        bowl.curve(
            to: CGPoint(x: leftStem, y: top + bowlRadius * 2),
            controlPoint1: CGPoint(x: leftStem - bowlWidth, y: top + bowlRadius * (1 + curve)),
            controlPoint2: CGPoint(x: leftStem - bowlWidth * curve, y: top + bowlRadius * 2)
        )
        bowl.close()
        bowl.fill()

        let stems = NSBezierPath()
        stems.move(to: CGPoint(x: leftStem, y: baseline))
        stems.line(to: CGPoint(x: leftStem, y: top + lineWidth / 2))
        stems.line(to: CGPoint(x: rightStem, y: top + lineWidth / 2))
        stems.move(to: CGPoint(x: rightStem, y: top + lineWidth / 2))
        stems.line(to: CGPoint(x: rightStem, y: baseline))
        stems.lineWidth = lineWidth
        stems.stroke()
    }
}
