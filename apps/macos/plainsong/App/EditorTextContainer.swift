import AppKit

/// 行末に句読点をぶら下げるため、行ごとに幅を渡す。TextKitは渡した幅に入るだけの字を組み、行頭に置けない字は前の字と一緒に次の行へ送る
/// NSTextViewはカーソルと選択範囲をテキストコンテナの内側に切り詰めて描くので、コンテナはぶら下げる余地の分だけ行より長くする
final nonisolated class EditorTextContainer: NSTextContainer {
    private static let hangingEms: CGFloat = 1.25

    /// 原稿用紙では、行の字数を`ManuscriptPaper`で決める
    var paper: ManuscriptPaper?

    var hangsPunctuation = true {
        didSet { fitSize() }
    }

    var cellWidth: CGFloat = 0 {
        didSet { fitSize() }
    }

    /// 版面の行の長さ。ぶら下げた字だけがここからはみ出す
    var lineLength: CGFloat = 0 {
        didSet { fitSize() }
    }

    private func fitSize() {
        let width = lineLength + (hangsPunctuation ? cellWidth * Self.hangingEms : 0)
        if size.width != width {
            size = NSSize(width: width, height: size.height)
        }
    }

    /// 単純な長方形のコンテナには、TextKitは行ごとの幅を尋ねない
    override var isSimpleRectangularTextContainer: Bool {
        false
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
        rect.size.width = lineLength
        guard let storage = (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
        else { return rect }
        if let paper {
            let cells = paper.cells(ofLineAt: characterIndex, in: storage.mutableString)
            if cells > 0 {
                // 丸め誤差で最後の字が次の行に送られないよう、次の字が入らない範囲で余裕を持たせる
                rect.size.width = (CGFloat(cells) + 0.25) * cellWidth
            }
        } else if hangsPunctuation, let width = hangingWidth(ofLineAt: characterIndex, in: storage, width: lineLength) {
            rect.size.width = width
        }
        return rect
    }

    /// 行に入るだけの字を入れ、あふれた字をぶら下げられるなら、その字まで入る幅を返す
    /// TextKitが行を組むたびに呼ぶので、行が決まるだけの字しか測らない
    private func hangingWidth(ofLineAt location: Int, in storage: NSTextStorage, width: CGFloat) -> CGFloat? {
        let string = storage.mutableString
        guard location < string.length else { return nil }
        let indent = indent(ofLineAt: location, in: storage)
        var length = 256
        while true {
            let end = min(location + length, string.length)
            let contentsEnd = (location ..< end).first { LineBreakRules.isLineBreak(string.character(at: $0)) } ?? end
            let contents = NSRange(location: location, length: contentsEnd - location)
            let line = measurable(storage.attributedSubstring(from: contents))
            let typesetter = CTTypesetterCreateWithAttributedString(line)
            let fitting = CTTypesetterSuggestClusterBreakWithOffset(
                typesetter,
                0,
                Double(width - indent),
                Double(indent)
            )
            // 次の字とその次の字まで読めば、ぶら下げられるかが決まる
            if contentsEnd == end, end < string.length, fitting + 2 >= line.length {
                length *= 2
                continue
            }
            guard fitting > 0, fitting < line.length else { return nil }
            let text = line.string as NSString
            let hanging = text.rangeOfComposedCharacterSequence(at: fitting)
            let next = NSMaxRange(hanging) < text.length ? Unicode.Scalar(text.character(at: NSMaxRange(hanging))) : nil
            guard LineBreakRules.canHang(Unicode.Scalar(text.character(at: fitting)), before: next) else { return nil }
            let hung = CTTypesetterCreateLineWithOffset(
                typesetter,
                CFRange(location: 0, length: NSMaxRange(hanging)),
                Double(indent)
            )
            // 測った幅ちょうどでは、丸め誤差でぶら下げた字が次の行に送られることがある。次の字が入らないよう、余裕はわずかにする
            return indent + CGFloat(CTLineGetTypographicBounds(hung, nil, nil, nil)) + 0.5
        }
    }

    /// 縦書きのTextKitは縦の字形で組み、句読点などの字送りが横書きと変わるので、測るときも縦の字形にする
    private func measurable(_ line: NSAttributedString) -> NSAttributedString {
        guard layoutOrientation == .vertical else { return line }
        let vertical = NSMutableAttributedString(attributedString: line)
        vertical.addAttribute(.verticalGlyphForm, value: 1, range: NSRange(location: 0, length: vertical.length))
        return vertical
    }

    /// 1行目の字下げは、`ParagraphIndentRules`が段落によって外す
    private func indent(ofLineAt location: Int, in storage: NSTextStorage) -> CGFloat {
        guard let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        else { return 0 }
        let startsParagraph = location == 0
            || LineBreakRules.isParagraphBreak(storage.mutableString.character(at: location - 1))
        guard startsParagraph else { return style.headIndent }
        return ParagraphIndentRules.indents(paragraphAt: location, in: storage) ? style.firstLineHeadIndent : 0
    }
}
