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
        case halfWidthPair = 3
        case emoji = 4
    }

    struct Run: Equatable {
        var range: NSRange
        var kind: Kind
    }

    private static let emojiFontName = "AppleColorEmoji"

    private struct Cell {
        var square: CGRect
        var line: NSTextLineFragment
        var lineOrigin: CGPoint
        var digits: NSAttributedString
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

    /// 原稿用紙では、マスに揃うよう字送りが1字分でない文字をすべて差し替える
    static func manuscriptRuns(in string: NSString, range: NSRange, isVertical: Bool, font: NSFont) -> [Run] {
        var pairs = runs(in: string, range: range).filter { $0.kind == .tateChuYoko }[...]
        var result: [Run] = []
        func append(_ kind: Kind, _ range: NSRange) {
            if let last = result.last, last.kind == kind, NSMaxRange(last.range) == range.location {
                result[result.count - 1].range.length += range.length
            } else {
                result.append(Run(range: range, kind: kind))
            }
        }
        let pairKind = isVertical ? Kind.tateChuYoko : .halfWidthPair
        forEachCharacter(in: range, of: string) { character, characterRange in
            if let pair = pairs.first, NSLocationInRange(characterRange.location, pair.range) {
                if characterRange.location == pair.range.location {
                    append(pairKind, pair.range)
                }
                if NSMaxRange(characterRange) >= NSMaxRange(pair.range) {
                    pairs.removeFirst()
                }
                return
            }
            guard let scalar = character.unicodeScalars.first, !isZeroWidth(scalar) else { return }
            if scalar.properties.isEmojiPresentation || character.unicodeScalars.contains("\u{FE0F}") {
                append(.emoji, characterRange)
            } else if isHalfWidthVoicedKana(character) {
                append(pairKind, characterRange)
            } else if isNarrow(scalar) || !fillsOneCell(character, in: font) {
                append(.upright, characterRange)
            }
        }
        return result
    }

    /// `ManuscriptPaper`と同じく`Character`を1字とする。NSStringの`byComposedCharacterSequences`は分け方が異なる
    static func forEachCharacter(
        in range: NSRange,
        of string: NSString,
        body: (_ character: Character, _ range: NSRange) -> Void
    ) {
        var location = range.location
        for character in string.substring(with: range) {
            let length = character.utf16.count
            body(character, NSRange(location: location, length: length))
            location += length
        }
    }

    static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .nonspacingMark, .enclosingMark: true
        default: false
        }
    }

    /// 全角の字形に差し替えると濁点も1字分になるので、半角のまま2桁の数字と同じく1マスに入れる
    private static func isHalfWidthVoicedKana(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        return scalars.count == 2 && isHalfWidthKana(scalars[0]) && (0xFF9E ... 0xFF9F).contains(scalars[1].value)
    }

    private static func isHalfWidthKana(_ scalar: Unicode.Scalar) -> Bool {
        (0xFF61 ... 0xFF9F).contains(scalar.value)
    }

    private static func isNarrow(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20 ... 0x7E, // 基本ラテン文字
             0x2010 ... 0x2027, 0x2030 ... 0x205E: // ダッシュ、三点リーダ、引用符など
            true
        default:
            isHalfWidthKana(scalar)
        }
    }

    private static func fillsOneCell(_ character: Character, in font: NSFont) -> Bool {
        guard character.unicodeScalars.count == 1 else {
            return abs(width(of: character, in: font) - font.pointSize) < advanceTolerance
        }
        let characters = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) else { return false }
        return abs(CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, nil, 1) - font.pointSize) < advanceTolerance
    }

    private static let advanceTolerance: CGFloat = 0.01

    private static func width(of character: Character, in font: NSFont) -> CGFloat {
        let string = NSAttributedString(string: String(character), attributes: [.font: font, .kern: 0])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil)
    }

    private static func isUpright(_ characters: [unichar]) -> Bool {
        if characters.count == 1 {
            return isDigit(characters[0]) || isUppercase(characters[0]) || isLowercase(characters[0])
        }
        return characters.allSatisfy { isDigit($0) || isUppercase($0) } && characters.contains(where: isUppercase)
    }

    static func isHalfWidthGraphic(_ character: unichar) -> Bool {
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
        return adding(feature: kind == .tateChuYoko || kind == .halfWidthPair ? "hwid" : "fwid", to: japanese)
    }

    /// 行のベースラインは行頭の字のフォントで決まるので、和文のフォントを指定したまま、実際に使うフォントはカスケードで渡す。字送りの固定はカスケードに引き継がれないので、両方に指定する
    /// 絵文字は文字サイズのままだとマスからはみ出すので0.85倍にする。カスケードは指定したフォントの大きさで描かれるので、行頭の絵文字の行だけベースラインが動く
    static func cellFont(for character: Character, kind: Kind, replacing font: NSFont, fixesAdvance: Bool) -> NSFont {
        let string = String(character)
        let size = kind == .emoji ? font.pointSize * 0.85 : font.pointSize
        let fallback = kind == .emoji
            ? NSFont(name: emojiFontName, size: size) ?? font
            : CTFontCreateForString(
                font,
                string as CFString,
                CFRange(location: 0, length: string.utf16.count)
            ) as NSFont
        // 基底の字を全角に差し替えると、合成する記号との位置が合わなくなる。ccmpは既定で有効なので、字形を変えずに差し替えたフォントと見分ける印になる
        let feature = character.unicodeScalars.count == 1 ? "fwid" : "ccmp"
        let primary = adding(feature: feature, to: NSFont(descriptor: font.fontDescriptor, size: size) ?? font)
        let natural = cascading(primary, to: fallback, advance: nil)
        if !fixesAdvance, width(of: character, in: natural) <= font.pointSize + advanceTolerance {
            return natural
        }
        let oneAdvance = cascading(primary, to: fallback, advance: font.pointSize)
        // 字送りの固定は字形ごとに効くので、字送りのある字形がいくつもある文字は割り戻す
        let width = width(of: character, in: oneAdvance)
        guard width > font.pointSize + advanceTolerance else { return oneAdvance }
        return cascading(primary, to: fallback, advance: font.pointSize * font.pointSize / width)
    }

    private static func cascading(_ primary: NSFont, to fallback: NSFont, advance: CGFloat?) -> NSFont {
        func fixing(_ descriptor: NSFontDescriptor) -> NSFontDescriptor {
            advance.map { descriptor.addingAttributes([.fixedAdvance: $0]) } ?? descriptor
        }
        let descriptor = fixing(primary.fontDescriptor).addingAttributes([
            .cascadeList: [fixing(fallback.fontDescriptor)],
        ])
        return NSFont(descriptor: descriptor, size: primary.pointSize) ?? primary
    }

    private static func adding(feature tag: String, to font: NSFont) -> NSFont {
        let feature: [NSFontDescriptor.FeatureKey: Any] = [
            NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): tag,
            NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): 1,
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    /// 本文のフォントにはOpenType機能を指定しないので、あれば差し替えたフォントとみなす
    static func isReplacement(_ font: NSFont) -> Bool {
        font.fontDescriptor.object(forKey: .featureSettings) != nil
    }
}

nonisolated extension UprightGlyphs {
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
        drawsOnlyDigits: Bool = false,
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
            if drawsOnlyDigits {
                fillCentered(cell.digits, in: context)
            } else {
                context.translateBy(x: -cell.square.midX, y: -cell.square.midY)
                cell.line.draw(at: cell.lineOrigin, in: context)
            }
            context.restoreGState()
        }
    }

    /// 字面の中心が今の原点にくる。本文は上から下へ組むので、Core Textの上向きの座標に合わせて反転する
    static func drawCentered(_ digits: NSAttributedString, in context: CGContext) {
        let line = CTLineCreateWithAttributedString(digits)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
        CTLineDraw(line, context)
    }

    /// 印刷では、切り抜いた行の数字もPDFのテキストに残るので、見せる数字は文字として重ねず、字形の輪郭で塗る
    private static func fillCentered(_ digits: NSAttributedString, in context: CGContext) {
        guard let font = digits.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return }
        let line = CTLineCreateWithAttributedString(digits)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let outlines = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var transform = CGAffineTransform(translationX: position.x - ink.midX, y: position.y - ink.midY)
                if let outline = CTFontCreatePathForGlyph(font, glyph, &transform) {
                    outlines.addPath(outline)
                }
            }
        }
        let color = digits.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        context.setFillColor((color ?? .black).cgColor)
        context.scaleBy(x: 1, y: -1)
        context.addPath(outlines)
        context.fillPath()
    }

    /// 隣り合う縦中横は属性が1つにつながるので、マスごとに分ける
    private static func cellRanges(of range: NSRange, in string: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var pendingDigit: Int?
        forEachCharacter(in: range, of: string) { character, characterRange in
            if let digit = pendingDigit {
                ranges.append(NSRange(location: digit, length: NSMaxRange(characterRange) - digit))
                pendingDigit = nil
            } else if character.isASCII, character.isNumber {
                pendingDigit = characterRange.location
            } else {
                ranges.append(characterRange)
            }
        }
        return ranges
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
                for range in cellRanges(of: range, in: paragraph.string as NSString) {
                    let digits = paragraph.attributedSubstring(from: range)
                    let ink = CTLineGetBoundsWithOptions(
                        CTLineCreateWithAttributedString(digits),
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
                        lineOrigin: bounds.origin,
                        digits: digits
                    ))
                }
            }
        }
        return cells
    }
}
