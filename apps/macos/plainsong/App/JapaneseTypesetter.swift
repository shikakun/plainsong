import AppKit

final class JapaneseTypesetter {
    private weak var textView: NSTextView?
    private var usesKerning = false
    private var isVertical = false
    private var manuscriptFont: NSFont?
    private var fixesCellAdvance = true
    private var replacements: [UprightGlyphs.Kind: [NSFont: NSFont]] = [:]
    private var cellFonts: [NSFont: [Character: NSFont]] = [:]

    init(textView: NSTextView) {
        self.textView = textView
    }

    /// 0を指定すると、欧文のカーニングに加えて、和文の約物の詰めと和欧間の空きも止まる
    private var baseKern: NSNumber? {
        usesKerning ? nil : 0
    }

    /// 印刷の原稿用紙は1字ずつマスの中心に置くので、1字分に収まる字の字送りを固定しない。固定すると、幅の狭い字が中心から左に寄る
    func update(usesKerning: Bool, isVertical: Bool, manuscriptFont: NSFont? = nil, fixesCellAdvance: Bool = true) {
        self.usesKerning = usesKerning
        self.isVertical = isVertical
        self.manuscriptFont = manuscriptFont
        self.fixesCellAdvance = fixesCellAdvance
        replacements.removeAll()
        cellFonts.removeAll()
        textView?.typingAttributes[.kern] = baseKern
        guard let storage = textView?.textStorage else { return }
        typeset(NSRange(location: 0, length: storage.length))
    }

    func plainAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        attributes[.kern] = baseKern
        if let font = attributes[.uprightOriginalFont] {
            attributes[.font] = font
        }
        attributes[.uprightGlyphs] = nil
        attributes[.uprightOriginalFont] = nil
        attributes[.verticalGlyphForm] = nil
        return attributes
    }

    func typeset(_ range: NSRange) {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let string = storage.mutableString
        let range = string.paragraphRange(for: NSIntersectionRange(range, NSRange(location: 0, length: storage.length)))
        // 未確定の文字を組むと、打鍵のたびに向きと字送りが変わる。確定すると本文の編集としてまた呼ばれる
        let composing = textView.hasMarkedText() ? textView.markedRange() : nil
        storage.beginEditing()
        let options: NSString.EnumerationOptions = [.byParagraphs, .substringNotRequired]
        string.enumerateSubstrings(in: range, options: options) { _, paragraph, enclosing, _ in
            self.typesetParagraph(paragraph, enclosing: enclosing, of: string, in: storage, composing: composing)
        }
        storage.endEditing()
    }

    private func typesetParagraph(
        _ paragraph: NSRange,
        enclosing: NSRange,
        of string: NSString,
        in storage: NSTextStorage,
        composing: NSRange?
    ) {
        var settled = IndexSet(integersIn: Range(paragraph) ?? 0 ..< 0)
        if let composing, let composingRange = Range(composing) {
            settled.remove(integersIn: composingRange)
        }
        let runs = runs(in: settled, of: string, storage: storage)
        restoreOriginalFonts(in: enclosing, of: storage, keeping: runs)
        runs.forEach { replaceFont(of: $0, in: storage) }

        var fixed = IndexSet()
        if usesKerning, isVertical {
            for index in Self.widenedStops(in: string, range: paragraph) where settled.contains(index) {
                fixed.insert(index)
            }
            runs.compactMap { Range($0.range) }.forEach { fixed.insert(integersIn: $0) }
        } else if !usesKerning {
            fixed.insert(integersIn: Range(enclosing) ?? 0 ..< 0)
        }
        var inherited = IndexSet(integersIn: Range(enclosing) ?? 0 ..< 0)
        inherited.subtract(fixed)
        fixed.rangeView.forEach { write(.kern, 0 as NSNumber, in: NSRange($0), of: storage) }
        inherited.rangeView.forEach { write(.kern, nil, in: NSRange($0), of: storage) }
    }

    private func runs(in settled: IndexSet, of string: NSString, storage: NSTextStorage) -> [UprightGlyphs.Run] {
        if let manuscriptFont {
            return settled.rangeView.flatMap {
                UprightGlyphs.manuscriptRuns(
                    in: string,
                    range: NSRange($0),
                    isVertical: isVertical,
                    font: manuscriptFont
                )
            }
        }
        guard isVertical else { return [] }
        return settled.rangeView.flatMap { UprightGlyphs.runs(in: string, range: NSRange($0)) }
            .filter { !isCode(at: $0.range.location, in: storage) }
    }

    private func restoreOriginalFonts(in range: NSRange, of storage: NSTextStorage, keeping runs: [UprightGlyphs.Run]) {
        storage.enumerateAttribute(.uprightGlyphs, in: range) { value, valueRange, _ in
            guard let kind = (value as? Int).flatMap(UprightGlyphs.Kind.init),
                  !runs.contains(UprightGlyphs.Run(range: valueRange, kind: kind))
            else { return }
            storage.enumerateAttribute(.uprightOriginalFont, in: valueRange) { original, originalRange, _ in
                guard let original else { return }
                storage.enumerateAttribute(.font, in: originalRange) { font, fontRange, _ in
                    if let font = font as? NSFont, UprightGlyphs.isReplacement(font) {
                        storage.addAttribute(.font, value: original, range: fontRange)
                    }
                }
            }
            for key in [NSAttributedString.Key.uprightGlyphs, .uprightOriginalFont, .verticalGlyphForm] {
                storage.removeAttribute(key, range: valueRange)
            }
        }
    }

    private func replaceFont(of run: UprightGlyphs.Run, in storage: NSTextStorage) {
        guard let font = storage.attribute(.font, at: run.range.location, effectiveRange: nil) as? NSFont
        else { return }
        let original = UprightGlyphs.isReplacement(font)
            ? storage.attribute(.uprightOriginalFont, at: run.range.location, effectiveRange: nil) as? NSFont ?? font
            : font
        if manuscriptFont != nil, run.kind == .upright || run.kind == .emoji {
            UprightGlyphs.forEachCharacter(in: run.range, of: storage.mutableString) { character, range in
                write(.font, cellFont(for: character, kind: run.kind, replacing: original), in: range, of: storage)
            }
        } else {
            let replacement = replacements[run.kind]?[original]
                ?? UprightGlyphs.font(for: run.kind, replacing: original)
            replacements[run.kind, default: [:]][original] = replacement
            write(.font, replacement, in: run.range, of: storage)
        }
        write(.uprightGlyphs, run.kind.rawValue as NSNumber, in: run.range, of: storage)
        write(.uprightOriginalFont, original, in: run.range, of: storage)
        write(.verticalGlyphForm, run.kind == .upright && isVertical ? 1 as NSNumber : nil, in: run.range, of: storage)
    }

    private func cellFont(for character: Character, kind: UprightGlyphs.Kind, replacing original: NSFont) -> NSFont {
        if let font = cellFonts[original]?[character] {
            return font
        }
        let font = UprightGlyphs.cellFont(
            for: character,
            kind: kind,
            replacing: original,
            fixesAdvance: fixesCellAdvance
        )
        cellFonts[original, default: [:]][character] = font
        return font
    }

    /// 同じ値でも書き込むとTextKitが段落を組み直すので、変わるところだけ書き込む
    private func write(
        _ key: NSAttributedString.Key,
        _ value: NSObject?,
        in range: NSRange,
        of storage: NSTextStorage
    ) {
        storage.enumerateAttribute(key, in: range) { current, currentRange, _ in
            guard current as? NSObject != value else { return }
            if let value {
                storage.addAttribute(key, value: value, range: currentRange)
            } else {
                storage.removeAttribute(key, range: currentRange)
            }
        }
    }

    /// 字間をTextKitに任せると、縦書きでは句読点が1.5字分に広がるので、字間を0にして1字分に戻す
    /// 終わり括弧が続くところと段落の末尾では広がらないので、TextKitの詰めを残す
    nonisolated static func widenedStops(in string: NSString, range: NSRange) -> [Int] {
        guard range.length > 1 else { return [] }
        return (range.location ..< NSMaxRange(range) - 1).filter { index in
            stops.contains(string.character(at: index)) && !closingBrackets.contains(string.character(at: index + 1))
        }
    }

    private nonisolated static let stops = Set("、。，．".utf16)
    private nonisolated static let closingBrackets = Set("」』）〕］｝〉》】〙〗〟｠⦆".utf16)

    private func isCode(at location: Int, in storage: NSTextStorage) -> Bool {
        let style = storage.attribute(.markdownStyle, at: location, effectiveRange: nil) as? Int ?? 0
        return !MarkdownSyntax.Style(rawValue: style).isDisjoint(with: [.code, .monospaced])
    }
}
