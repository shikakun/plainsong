import AppKit

/// 最後の段落を消して空の行が残ると、TextKit 2はその行に行間を足さずに組むので、組み直させる
final nonisolated class TrailingNewlineContentStorage: NSTextContentStorage {
    override func processEditing(
        for textStorage: NSTextStorage,
        edited editMask: NSTextStorageEditActions,
        range newCharRange: NSRange,
        changeInLength delta: Int,
        invalidatedRange invalidatedCharRange: NSRange
    ) {
        super.processEditing(
            for: textStorage,
            edited: editMask,
            range: newCharRange,
            changeInLength: delta,
            invalidatedRange: invalidatedCharRange
        )
        let string = textStorage.mutableString
        guard editMask.contains(.editedCharacters),
              NSMaxRange(newCharRange) == string.length,
              string.length > 0,
              string.character(at: string.length - 1) == 0x0A,
              let newline = location(documentRange.endLocation, offsetBy: -1),
              let range = NSTextRange(location: newline, end: documentRange.endLocation)
        else { return }
        textLayoutManagers.forEach { $0.invalidateLayout(for: range) }
    }
}

/// 行間を足すと、TextKit 2はカーソルと選択範囲を行間の分だけ文字の上に伸ばすので、文字1行分の高さに縮めて下に寄せる
final nonisolated class LineHeightSegmentLayoutManager: NSTextLayoutManager {
    var lineHeight: CGFloat = 0

    override func enumerateTextSegments(
        in textRange: NSTextRange,
        type: NSTextLayoutManager.SegmentType,
        options: NSTextLayoutManager.SegmentOptions = [],
        using block: (NSTextRange?, CGRect, CGFloat, NSTextContainer) -> Bool
    ) {
        guard type == .standard || type == .selection else {
            super.enumerateTextSegments(in: textRange, type: type, options: options, using: block)
            return
        }
        super.enumerateTextSegments(in: textRange, type: type, options: options) { range, frame, baseline, container in
            let spacing = max(frame.height - lineHeight, 0)
            var trimmed = frame
            trimmed.origin.y += spacing
            trimmed.size.height -= spacing
            return block(range, trimmed, baseline - spacing, container)
        }
    }
}

/// 和文の始め括弧か空白で始まる段落は、1行目を下げずに組む。組むときの段落だけを差し替え、本文の属性は書き換えない
/// 状態を持たないので、どのウィンドウも1つを使い回す。コンテンツストレージはデリゲートを弱参照で持つが、共有のインスタンスなので解放されない
final nonisolated class ParagraphIndentRules: NSObject, NSTextContentStorageDelegate, Sendable {
    static let shared = ParagraphIndentRules()

    /// JLREQの始め括弧類から、欧文の括弧と引用符を除いたもの。欧文の段落は、引用符で始まっても下げる
    private static let openingBrackets = Set("「『（〔［｛〈《【〘〖〝｟⦅".utf16)

    /// 空白で始まる段落は、自分で字下げしたものとして二重に下げない
    private static func indents(paragraphStartingWith character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }
        return !openingBrackets.contains(character) && !CharacterSet.whitespaces.contains(scalar)
    }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage,
              range.length > 0,
              !Self.indents(paragraphStartingWith: storage.mutableString.character(at: range.location)),
              let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
              as? NSParagraphStyle,
              style.firstLineHeadIndent > 0,
              let flush = style.mutableCopy() as? NSMutableParagraphStyle
        else { return nil }
        flush.firstLineHeadIndent = 0
        let paragraph = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        paragraph.addAttribute(.paragraphStyle, value: flush, range: NSRange(location: 0, length: paragraph.length))
        return NSTextParagraph(attributedString: paragraph)
    }
}

extension NSTextView {
    /// textContainerInsetは左右に同じ幅しか空けられないので、テキストコンテナの幅で右の余白を決める
    /// ウィンドウの大きさを変えているあいだは何度も呼ばれるので、変わったときだけ渡す
    func setHorizontalInsets(leading: CGFloat, trailing: CGFloat, clipWidth: CGFloat) {
        guard let textContainer else { return }
        let tracksWidth = leading == trailing
        if textContainer.widthTracksTextView != tracksWidth {
            textContainer.widthTracksTextView = tracksWidth
        }
        let width = max(clipWidth - leading - trailing, 0)
        if textContainer.size.width != width {
            textContainer.size = NSSize(width: width, height: textContainer.size.height)
        }
        if textContainerInset.width != leading {
            textContainerInset = NSSize(width: leading, height: 0)
        }
    }

    var nonEmptySelectedRanges: [NSRange] {
        selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
    }

    /// 変換中に本文を書き換えると、入力メソッドが変換している範囲と本文が食い違うので、先に変換を取り消す
    func discardMarkedTextIfNeeded() {
        if hasMarkedText() {
            inputContext?.discardMarkedText()
        }
    }
}
