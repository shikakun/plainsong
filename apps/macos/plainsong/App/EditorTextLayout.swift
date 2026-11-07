import AppKit

/// 縦書きは右の列から読むので、クリップビューの幅が変わっても右端を保つ。NSClipViewは原点を保つので、左端が残って右の列が見切れる
final class EditorClipView: NSClipView {
    override func setFrameSize(_ newSize: NSSize) {
        let rightEdge = bounds.maxX
        super.setFrameSize(newSize)
        guard (documentView as? NSTextView)?.layoutOrientation == .vertical else { return }
        var bounds = bounds
        bounds.origin.x = rightEdge - bounds.width
        scroll(to: constrainBoundsRect(bounds).origin)
        enclosingScrollView?.reflectScrolledClipView(self)
    }
}

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

/// 行間を足すと、TextKit 2はカーソルと選択範囲を行間の分だけ文字の上に伸ばすので、文字1行分の高さに縮める
/// 行の高さを固定すると、ベースラインは欧文フォントのディセントで決まり、和文の字面が帯の中心からずれるので、帯を字面の中心に合わせる
final nonisolated class LineHeightSegmentLayoutManager: NSTextLayoutManager {
    /// 帯は行の外へ少しはみ出す。テキストビューの外には描けないので、先頭と末尾の行の分をテキストコンテナで空ける
    static let bandOverhang: CGFloat = 2

    var lineHeight: CGFloat = 0
    /// 和文の字面の中心の、ベースラインからの高さ
    var japaneseMiddle: CGFloat = 0

    /// 縦書きでは、行の中心がglyphOriginの高さにくる。空の行は、行間を文字の上に分けず行の高さに含めて組むので、下端から求める
    /// 横書きでは、同じ計算でベースラインの位置になる
    func verticalMiddle(of line: NSTextLineFragment, in bounds: CGRect, isEmpty: Bool) -> CGFloat {
        (isEmpty ? bounds.maxY - lineHeight : bounds.minY) + line.glyphOrigin.y
    }

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
            let position = baselinePosition(of: frame) ?? frame.minY + baseline
            let middle = position - (container.layoutOrientation == .vertical ? 0 : japaneseMiddle)
            var band = frame
            band.size.height -= max(frame.height - lineHeight, 0)
            // 帯の端がにじまないよう、TextKitが組む行の位置と同じく整数にする
            band.origin.y = (middle - band.height / 2).rounded()
            return block(range, band, position - band.minY, container)
        }
    }

    /// 空の文書にはレイアウトフラグメントがない
    private func baselinePosition(of frame: CGRect) -> CGFloat? {
        let bottom = frame.maxY - 1
        guard let fragment = textLayoutFragment(for: CGPoint(x: frame.midX, y: bottom)),
              let paragraph = fragment.textElement as? NSTextParagraph
        else { return nil }
        let top = fragment.layoutFragmentFrame.minY
        guard let line = fragment.textLineFragments.last(where: { top + $0.typographicBounds.minY <= bottom })
        else { return nil }
        let isEmpty = paragraph.attributedString.string.allSatisfy(\.isNewline)
        return verticalMiddle(of: line, in: line.typographicBounds, isEmpty: isEmpty) + top
    }
}

/// 和文の始め括弧か空白で始まる段落と、Markdownの見出しやリストなどの行は、1行目を下げずに組む。組むときの段落だけを差し替え、本文の属性は書き換えない
/// 状態を持たないので、どのウィンドウも1つを使い回す。コンテンツストレージはデリゲートを弱参照で持つが、共有のインスタンスなので解放されない
final nonisolated class ParagraphIndentRules: NSObject, NSTextContentStorageDelegate, Sendable {
    static let shared = ParagraphIndentRules()

    /// JLREQの始め括弧類から、欧文の括弧と引用符を除いたもの。欧文の段落は、引用符で始まっても下げる
    private static let openingBrackets = Set("「『（〔［｛〈《【〘〖〝｟⦅".utf16)

    /// 空白で始まる段落は、自分で字下げしたものとして二重に下げない
    static func indents(paragraphStartingWith character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }
        return !openingBrackets.contains(character) && !CharacterSet.whitespaces.contains(scalar)
    }

    private static func indents(paragraphAt location: Int, in storage: NSTextStorage) -> Bool {
        let style = storage.attribute(.markdownStyle, at: location, effectiveRange: nil) as? Int ?? 0
        return indents(paragraphStartingWith: storage.mutableString.character(at: location))
            && !MarkdownSyntax.Style(rawValue: style).contains(.unindented)
    }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage,
              range.length > 0,
              !Self.indents(paragraphAt: range.location, in: storage),
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

extension EditorWindowController {
    /// TextKit 2が組む、行間を含まない1行の高さを求める
    private static let metrics = NSLayoutManager()

    /// 明朝体の欧文は文字サイズによって行の高さが1ptずれるので、フォントを切り替えても行送りが変わらないようゴシック体の高さに揃える
    static func lineHeight(of settings: EditorSettings) -> CGFloat {
        metrics.defaultLineHeight(for: EditorSettings.FontFamily.sansSerif.font(ofSize: settings.fontSize))
    }

    /// scrollableTextView()ではレイアウトマネージャーを差し替えられないので、同じ構成を自分で組む
    static func makeTextView() -> (NSTextView, LineHeightSegmentLayoutManager) {
        let layoutManager = LineHeightSegmentLayoutManager()
        let contentStorage = TrailingNewlineContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.delegate = ParagraphIndentRules.shared
        let container = ManuscriptTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return (textView, layoutManager)
    }
}

extension NSTextView {
    /// textContainerInsetは行頭と行末に同じ幅しか空けられないので、行末の余白はテキストコンテナの幅で決める
    /// 縦書きでもテキストコンテナの幅が行の長さになるので、clipLengthには行に使える高さを渡す
    /// ウィンドウの大きさを変えているあいだは何度も呼ばれるので、変わったときだけ渡す
    func setLineInsets(leading: CGFloat, trailing: CGFloat, clipLength: CGFloat) {
        guard let textContainer else { return }
        let tracksWidth = leading == trailing
        if textContainer.widthTracksTextView != tracksWidth {
            textContainer.widthTracksTextView = tracksWidth
        }
        let width = max(clipLength - leading - trailing, 0)
        if textContainer.size.width != width {
            textContainer.size = NSSize(width: width, height: textContainer.size.height)
        }
        let inset = NSSize(width: leading, height: LineHeightSegmentLayoutManager.bandOverhang)
        if textContainerInset != inset {
            textContainerInset = inset
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
