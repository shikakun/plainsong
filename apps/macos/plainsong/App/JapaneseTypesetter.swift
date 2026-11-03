import AppKit

/// 本文の字間と、縦書きで立てる半角英数の属性を付ける。本文の字間はここだけが決める
/// 和文の約物の詰めと和欧間の空きは、TextKitに任せる
/// 属性の変更なので、TextStoreは記録せず、取り消しの履歴にも入らない
final class JapaneseTypesetter {
    private weak var textView: NSTextView?
    private var usesKerning = false
    private var isVertical = false
    private var pendingRange: NSRange?
    private var pendingTask: Task<Void, Never>?
    private var editingObservation: (any NSObjectProtocol)?

    init(textView: NSTextView) {
        self.textView = textView
        // 本文はメインスレッドでしか変えないので、通知もメインスレッドで届く
        editingObservation = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storageDidProcessEditing() }
        }
    }

    /// 0を指定すると、欧文のカーニングに加えて、和文の約物の詰めと和欧間の空きも止まる
    private var baseKern: NSNumber? {
        usesKerning ? nil : 0
    }

    func update(usesKerning: Bool, isVertical: Bool) {
        self.usesKerning = usesKerning
        self.isVertical = isVertical
        textView?.typingAttributes[.kern] = baseKern
        guard let storage = textView?.textStorage else { return }
        typeset(NSRange(location: 0, length: storage.length))
    }

    /// 入力する文字は前の文字の属性を引き継ぐので、字間と、立てるために差し替えたフォントを戻す
    func plainAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        attributes[.kern] = baseKern
        if let font = attributes[.uprightOriginalFont] {
            attributes[.font] = font
        }
        attributes[.uprightGlyphs] = nil
        attributes[.uprightOriginalFont] = nil
        return attributes
    }

    /// `MarkdownHighlighter`が見出しなどのフォントを変えたあとにも呼ばれ、文字サイズに合わせて字間を決め直す
    func typeset(_ range: NSRange) {
        guard let storage = textView?.textStorage, storage.length > 0 else { return }
        let string = storage.string as NSString
        let range = string.paragraphRange(for: NSIntersectionRange(range, NSRange(location: 0, length: storage.length)))
        storage.beginEditing()
        if let baseKern {
            storage.addAttribute(.kern, value: baseKern, range: range)
        } else {
            storage.removeAttribute(.kern, range: range)
        }
        restoreOriginalFonts(in: range, of: storage)
        string.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, paragraph, _, _ in
            self.typesetParagraph(paragraph, of: string, in: storage)
        }
        storage.endEditing()
    }

    private func typesetParagraph(_ paragraph: NSRange, of string: NSString, in storage: NSTextStorage) {
        guard isVertical else { return }
        if usesKerning {
            for index in Self.widenedStops(in: string, range: paragraph) {
                storage.addAttribute(.kern, value: 0, range: NSRange(location: index, length: 1))
            }
        }
        let upright = UprightGlyphs.runs(in: string, range: paragraph)
            .filter { !isCode(at: $0.range.location, in: storage) }
        for run in upright {
            guard let font = storage.attribute(.font, at: run.range.location, effectiveRange: nil) as? NSFont
            else { continue }
            storage.addAttributes([
                .font: UprightGlyphs.font(for: run.kind, replacing: font),
                .kern: 0,
                .uprightGlyphs: run.kind.rawValue,
                .uprightOriginalFont: font,
            ], range: run.range)
        }
    }

    /// `applyFont(of:)`や`MarkdownHighlighter`がフォントを付け直したところは、そのフォントを残す
    private func restoreOriginalFonts(in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.uprightOriginalFont, in: range) { original, originalRange, _ in
            guard let original else { return }
            storage.enumerateAttribute(.font, in: originalRange) { font, fontRange, _ in
                if let font = font as? NSFont, UprightGlyphs.isReplacement(font) {
                    storage.addAttribute(.font, value: original, range: fontRange)
                }
            }
        }
        storage.removeAttribute(.uprightGlyphs, range: range)
        storage.removeAttribute(.uprightOriginalFont, range: range)
    }

    /// 縦書きで字間をTextKitに任せると、句読点が1.5字分の幅になるので、字間を0にして1字分に戻す
    /// 終わり括弧が続くところと段落の末尾では起きないので、TextKitの詰めを残す
    nonisolated static func widenedStops(in string: NSString, range: NSRange) -> [Int] {
        guard range.length > 1 else { return [] }
        return (range.location ..< NSMaxRange(range) - 1).filter { index in
            stops.contains(string.character(at: index)) && !closingBrackets.contains(string.character(at: index + 1))
        }
    }

    private nonisolated static let stops = Set("、。，．".utf16)
    private nonisolated static let closingBrackets = Set("」』）〕］｝〉》】〙〗〟｠⦆".utf16)

    /// Markdownのコードは、書いたとおりに読めるよう横倒しのままにする
    private func isCode(at location: Int, in storage: NSTextStorage) -> Bool {
        let style = storage.attribute(.markdownStyle, at: location, effectiveRange: nil) as? Int ?? 0
        return !MarkdownSyntax.Style(rawValue: style).isDisjoint(with: [.code, .monospaced])
    }

    private func storageDidProcessEditing() {
        guard let storage = textView?.textStorage, storage.editedMask.contains(.editedCharacters) else { return }
        let edited = storage.editedRange
        pendingRange = pendingRange.map {
            NSUnionRange(MarkdownHighlighter.range($0, adjustedFor: edited, delta: storage.changeInLength), edited)
        } ?? edited
        pendingTask = pendingTask ?? Task { [weak self] in
            self?.typesetPending()
        }
    }

    private func typesetPending() {
        pendingTask = nil
        guard let pendingRange else { return }
        self.pendingRange = nil
        typeset(pendingRange)
    }
}
