import AppKit

extension NSAttributedString.Key {
    /// 縦書きで立てる半角英数。値は`UprightGlyphs.Kind`
    nonisolated static let uprightGlyphs = NSAttributedString.Key("PlainsongUprightGlyphs")
    /// 立てるためにフォントを差し替えた文字の、元のフォント
    nonisolated static let uprightOriginalFont = NSAttributedString.Key("PlainsongUprightOriginalFont")
}

/// TextKitは縦書きの半角英数を横倒しに描くので、立てる文字は1文字分の升目で送るフォントに差し替えておき、
/// 描くときに升目から元の字形を除いて、立てた字形を描き直す
nonisolated enum UprightGlyphs {
    enum Kind: Int {
        case upright = 1
        case tateChuYoko = 2
    }

    struct Run: Equatable {
        var range: NSRange
        var kind: Kind
    }

    private struct Cell {
        /// 元の描画を除く範囲。行の幅いっぱいに取る
        var band: CGRect
        /// 文字を置く、文字サイズの正方形
        var square: CGRect
        var range: NSRange
        var kind: Kind
    }

    /// 空白や和文で区切られた半角のまとまりごとに決め、記号を含むまとまりは横倒しのままにする
    /// 2桁の数字は縦中横、1文字の英数と小文字を含まない英字は1字ずつ正立にする（JLREQ 3.2.3）
    static func runs(in string: NSString, range: NSRange) -> [Run] {
        var runs: [Run] = []
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            guard isHalfWidthGraphic(string.character(at: location)) else {
                location += 1
                continue
            }
            var tokenEnd = location + 1
            while tokenEnd < end, isHalfWidthGraphic(string.character(at: tokenEnd)) {
                tokenEnd += 1
            }
            let token = NSRange(location ..< tokenEnd)
            let characters = (location ..< tokenEnd).map { string.character(at: $0) }
            if characters.count == 2, characters.allSatisfy(isDigit) {
                runs.append(Run(range: token, kind: .tateChuYoko))
            } else if isUpright(characters) {
                runs.append(Run(range: token, kind: .upright))
            }
            location = tokenEnd
        }
        return runs
    }

    private static func isUpright(_ characters: [unichar]) -> Bool {
        if characters.count == 1 {
            return isDigit(characters[0]) || isUppercase(characters[0]) || isLowercase(characters[0])
        }
        return characters.allSatisfy { isDigit($0) || isUppercase($0) } && characters.contains(where: isUppercase)
    }

    private static func isHalfWidthGraphic(_ character: unichar) -> Bool {
        (0x21 ... 0x7E).contains(character)
    }

    private static func isDigit(_ character: unichar) -> Bool {
        (0x30 ... 0x39).contains(character)
    }

    private static func isUppercase(_ character: unichar) -> Bool {
        (0x41 ... 0x5A).contains(character)
    }

    private static func isLowercase(_ character: unichar) -> Bool {
        (0x61 ... 0x7A).contains(character)
    }

    /// 立てる文字は、和文のフォントの全角の字形にして、送りを1文字分にする。縦中横の数字は半角の字形にして、2桁で1文字分にする
    /// 字形の幅で送るので、カーソルや選択範囲も1文字分の升目に沿う
    static func font(for kind: Kind, replacing font: NSFont) -> NSFont {
        let japanese = CTFontCreateForString(font, "あ" as CFString, CFRange(location: 0, length: 1)) as NSFont
        let tag = kind == .tateChuYoko ? "hwid" : "fwid"
        let feature: [NSFontDescriptor.FeatureKey: Any] = [
            NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): tag,
            NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): 1,
        ]
        let descriptor = japanese.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    /// 本文のフォントは字形の機能を指定しないので、指定があれば立てるために差し替えたフォント
    static func isReplacement(_ font: NSFont) -> Bool {
        font.fontDescriptor.object(forKey: .featureSettings) != nil
    }

    static func draw(_ fragment: NSTextLayoutFragment, at point: CGPoint, in context: CGContext, drawText: () -> Void) {
        guard let paragraph = (fragment.textElement as? NSTextParagraph)?.attributedString else {
            drawText()
            return
        }
        let cells = cells(of: fragment, paragraph: paragraph, at: point)
        guard !cells.isEmpty else {
            drawText()
            return
        }
        context.saveGState()
        let clip = CGMutablePath()
        clip.addRect(context.boundingBoxOfClipPath)
        cells.forEach { clip.addRect($0.band) }
        context.addPath(clip)
        context.clip(using: .evenOdd)
        drawText()
        context.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let colors = Colors(fragment: fragment)
        for cell in cells {
            draw(cell, of: paragraph, colors: colors, in: context)
        }
    }

    private static func cells(
        of fragment: NSTextLayoutFragment,
        paragraph: NSAttributedString,
        at point: CGPoint
    ) -> [Cell] {
        var cells: [Cell] = []
        for line in fragment.textLineFragments {
            let bounds = line.typographicBounds.offsetBy(dx: point.x, dy: point.y)
            // 縦書きでは、行の中心がglyphOriginの高さに来る
            let center = bounds.minY + line.glyphOrigin.y
            paragraph.enumerateAttribute(.uprightGlyphs, in: line.characterRange) { value, range, _ in
                guard let kind = (value as? Int).flatMap(Kind.init),
                      let font = paragraph.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                else { return }
                let ranges = kind == .tateChuYoko
                    ? [range]
                    : (range.location ..< NSMaxRange(range)).map { NSRange(location: $0, length: 1) }
                for range in ranges {
                    let minX = bounds.minX + line.locationForCharacter(at: range.location).x
                    let maxX = bounds.minX + line.locationForCharacter(at: NSMaxRange(range)).x
                    let size = font.pointSize
                    cells.append(Cell(
                        band: CGRect(x: minX, y: bounds.minY, width: maxX - minX, height: bounds.height),
                        square: CGRect(x: minX, y: center - size / 2, width: maxX - minX, height: size),
                        range: range,
                        kind: kind
                    ))
                }
            }
        }
        return cells
    }

    private static func draw(_ cell: Cell, of paragraph: NSAttributedString, colors: Colors, in context: CGContext) {
        if let background = colors.background(at: cell.range.location) {
            background.setFill()
            cell.band.fill()
        }
        let attributes = paragraph.attributes(at: cell.range.location, effectiveRange: nil)
        let color = colors.foreground(at: cell.range.location)
            ?? attributes[.foregroundColor] as? NSColor
            ?? NSColor.textColor
        let text = (paragraph.string as NSString).substring(with: cell.range)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: attributes[.font] ?? NSFont.systemFont(ofSize: cell.square.height),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
        // 和文の仮想ボディの中央に置くよう、字面の外形の中心を正方形の中心に合わせる。外形はベースラインの左端を原点に、上を正とする
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: cell.square.midX, y: cell.square.midY)
        // 座標は縦書きでも横書きの向きのままなので、表示で立つよう反対に回す
        context.rotate(by: -.pi / 2)
        // 縦中横の数字は、1文字分の幅に収まらなければ縮める
        let side = min(cell.square.width, cell.square.height)
        let scale = cell.kind == .tateChuYoko ? min(1, side / max(advance, 1)) : 1
        // 本文の座標は上下が反転しているので、Core Textの向きに戻す
        context.scaleBy(x: scale, y: -1)
        color.setFill()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// 検索の印などのレンダリング属性と、選択した文字の色。元の描画を除いた升目にも同じ色を付ける
    private struct Colors {
        private var backgrounds: [(NSRange, NSColor)] = []
        private var foregrounds: [(NSRange, NSColor)] = []

        init(fragment: NSTextLayoutFragment) {
            guard let layoutManager = fragment.textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { return }
            let start = fragment.rangeInElement.location
            let end = fragment.rangeInElement.endLocation
            func paragraphRange(_ range: NSTextRange) -> NSRange {
                let location = contentManager.offset(from: start, to: range.location)
                let length = contentManager.offset(from: range.location, to: range.endLocation)
                return NSRange(location: location, length: length)
            }
            layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
                guard range.location.compare(end) == .orderedAscending else { return false }
                if let color = attributes[.backgroundColor] as? NSColor {
                    backgrounds.append((paragraphRange(range), color))
                }
                if let color = attributes[.foregroundColor] as? NSColor {
                    foregrounds.append((paragraphRange(range), color))
                }
                return true
            }
            // 選択した文字の色はレンダリング属性にないので、テキストビューの設定から付ける
            // NSTextViewはメインスレッドで描くが、レイアウトフラグメントはスレッドを限らないので確かめる
            guard Thread.isMainThread,
                  let textView = layoutManager.textContainer?.textView,
                  let color = MainActor.assumeIsolated({ () -> NSColor? in
                      guard textView.window?.isKeyWindow == true,
                            textView.window?.firstResponder === textView
                      else { return nil }
                      return textView.selectedTextAttributes[.foregroundColor] as? NSColor
                  })
            else { return }
            for selection in layoutManager.textSelections {
                for range in selection.textRanges where !range.isEmpty {
                    foregrounds.append((paragraphRange(range), color))
                }
            }
        }

        func background(at location: Int) -> NSColor? {
            backgrounds.last { NSLocationInRange(location, $0.0) }?.1
        }

        func foreground(at location: Int) -> NSColor? {
            foregrounds.last { NSLocationInRange(location, $0.0) }?.1
        }
    }
}
