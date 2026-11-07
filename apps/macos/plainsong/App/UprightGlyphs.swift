import AppKit

extension NSAttributedString.Key {
    /// 値は`UprightGlyphs.Kind`のrawValue
    nonisolated static let uprightGlyphs = NSAttributedString.Key("PlainsongUprightGlyphs")
    nonisolated static let uprightOriginalFont = NSAttributedString.Key("PlainsongUprightOriginalFont")
}

/// TextKitは縦書きの半角英数を横に倒して組むので、立てる文字は字送りが1字分のフォントに差し替える。縦中横には立てる属性がないので、描くときに回転させる
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
        var square: CGRect
        var line: NSTextLineFragment
        var lineOrigin: CGPoint
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

    /// 回転させて描き直せば、選択中の文字色や描画用の属性の色をTextKitが塗り分ける
    static func draw(_ fragment: NSTextLayoutFragment, at point: CGPoint, in context: CGContext, drawText: () -> Void) {
        guard let paragraph = (fragment.textElement as? NSTextParagraph)?.attributedString else {
            drawText()
            return
        }
        draw(fragment.textLineFragments, of: paragraph, at: point, in: context, drawText: drawText)
    }

    static func draw(
        _ lines: [NSTextLineFragment],
        of paragraph: NSAttributedString,
        at point: CGPoint,
        in context: CGContext,
        drawText: () -> Void
    ) {
        let cells = tateChuYokoCells(of: lines, paragraph: paragraph, at: point)
        guard !cells.isEmpty else {
            drawText()
            return
        }
        context.saveGState()
        let clip = CGMutablePath()
        clip.addRect(context.boundingBoxOfClipPath)
        cells.forEach { clip.addRect($0.square) }
        context.addPath(clip)
        context.clip(using: .evenOdd)
        drawText()
        context.restoreGState()

        for cell in cells {
            context.saveGState()
            context.clip(to: cell.square)
            context.translateBy(x: cell.square.midX, y: cell.square.midY)
            context.rotate(by: -.pi / 2)
            context.translateBy(x: -cell.square.midX, y: -cell.square.midY)
            cell.line.draw(at: cell.lineOrigin, in: context)
            context.restoreGState()
        }
    }

    private static func tateChuYokoCells(
        of lines: [NSTextLineFragment],
        paragraph: NSAttributedString,
        at point: CGPoint
    ) -> [Cell] {
        var cells: [Cell] = []
        for line in lines {
            let bounds = line.typographicBounds.offsetBy(dx: point.x, dy: point.y)
            // 縦書きでは、行の中心がglyphOriginの高さにくる
            let center = bounds.minY + line.glyphOrigin.y
            paragraph.enumerateAttribute(.uprightGlyphs, in: line.characterRange) { value, range, _ in
                guard value as? Int == Kind.tateChuYoko.rawValue,
                      let font = paragraph.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                else { return }
                let ink = CTLineGetBoundsWithOptions(
                    CTLineCreateWithAttributedString(paragraph.attributedSubstring(from: range)),
                    .useGlyphPathBounds
                )
                let minX = bounds.minX + line.locationForCharacter(at: range.location).x
                let advance = bounds.minX + line.locationForCharacter(at: NSMaxRange(range)).x - minX
                // 字面ちょうどで切ると、倒れた字形の輪郭が残る。倒れた字面は列の中心から少しずれるので、高さにはさらに余裕を持たせる
                let side = min(advance, max(ink.width + font.pointSize / 16, ink.height + font.pointSize / 10))
                let inkCenter = minX + ink.midX
                cells.append(Cell(
                    square: CGRect(x: inkCenter - side / 2, y: center - side / 2, width: side, height: side),
                    line: line,
                    lineOrigin: bounds.origin
                ))
            }
        }
        return cells
    }
}
