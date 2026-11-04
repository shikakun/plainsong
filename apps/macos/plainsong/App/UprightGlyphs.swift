import AppKit

extension NSAttributedString.Key {
    /// 値は`UprightGlyphs.Kind`のrawValue
    nonisolated static let uprightGlyphs = NSAttributedString.Key("PlainsongUprightGlyphs")
    nonisolated static let uprightOriginalFont = NSAttributedString.Key("PlainsongUprightOriginalFont")
}

/// TextKitは縦書きの半角英数を横に倒して描くので、立てる文字は字送りが1字分のフォントに差し替え、
/// 描くときに元の字形を消して立てた字形を描き直す
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
        var band: CGRect
        var square: CGRect
        var range: NSRange
        var kind: Kind
    }

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

    /// 字間で字送りを調整するとカーソルや選択範囲がずれるので、字送りが1字分の字形に差し替える
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

    /// 本文のフォントにはOpenType機能を指定しないので、指定があれば差し替えたフォントとみなす
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
            // 縦書きでは、行の中心がglyphOriginの高さにくる
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
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: cell.square.midX, y: cell.square.midY)
        context.rotate(by: -.pi / 2)
        let side = min(cell.square.width, cell.square.height)
        let scale = cell.kind == .tateChuYoko ? min(1, side / max(advance, 1)) : 1
        context.scaleBy(x: scale, y: -1)
        color.setFill()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

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
            // 選択した文字の色はrenderingAttributesに含まれないので、selectedTextAttributesから取る
            // NSTextLayoutFragmentはメインスレッド以外で描かれることもあるので確かめる
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
