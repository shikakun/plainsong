import AppKit

/// 本文の左の余白に重ね、改行のあとに始まる行に番号を描く。描くのは見えている行だけ
final class LineNumberView: NSView {
    private let textView: NSTextView
    /// 前回描いたときの、先頭の段落の位置と行番号。そこから数えれば、文書の先頭から数え直さずに済む
    private var anchor: (location: Int, number: Int)?

    private var font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    /// 本文の文字サイズ。行番号は1段階小さいサイズにし、いちばん小さいサイズでは同じにする
    var fontSize: CGFloat = 0 {
        didSet {
            guard fontSize != oldValue else { return }
            let size = EditorSettings.fontSizes.last { $0 < fontSize } ?? fontSize
            font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        autoresizingMask = [.height]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
        if let clipView = textView.enclosingScrollView?.contentView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// U+2028とU+2029は、TextKit 2では段落を分けずに段落の中で行を変える。\r\nは1つと数える
    nonisolated static func lineBreakCount(in string: NSString, range: NSRange) -> Int {
        var count = 0
        var previous: unichar = 0
        var location = range.location
        withUnsafeTemporaryAllocation(of: unichar.self, capacity: 4096) { buffer in
            guard let base = buffer.baseAddress else { return }
            while location < NSMaxRange(range) {
                let length = min(buffer.count, NSMaxRange(range) - location)
                string.getCharacters(base, range: NSRange(location: location, length: length))
                for character in buffer.prefix(length) {
                    if isLineBreak(character), character != 0x0A || previous != 0x0D {
                        count += 1
                    }
                    previous = character
                }
                location += length
            }
        }
        return count
    }

    private nonisolated static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029
    }

    @objc private func textDidProcessEditing(_ notification: Notification) {
        needsDisplay = true
        guard let anchor, let storage = notification.object as? NSTextStorage,
              storage.editedMask.contains(.editedCharacters),
              storage.editedRange.location < anchor.location
        else { return }
        self.anchor = nil
    }

    @objc private func clipViewBoundsDidChange(_: Notification) {
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let string = textView.textStorage?.mutableString,
              let bodyFont = textView.typingAttributes[.font] as? NSFont
        else { return }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let documentStart = contentManager.documentRange.location
        guard string.length > 0 else {
            drawEmptyDocumentNumber(layoutManager: layoutManager, at: documentStart, origin: origin, font: bodyFont)
            return
        }
        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY - origin.y))?
            .rangeInElement.location
            ?? layoutManager.textViewportLayoutController.viewportRange?.location
            ?? documentStart
        var number: Int?
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            guard frame.minY < visible.maxY,
                  let paragraph = (fragment.textElement as? NSTextParagraph)?.attributedString.string as NSString?
            else { return false }
            var current = number ?? lineNumber(
                at: contentManager.offset(from: documentStart, to: fragment.rangeInElement.location),
                in: string
            ) - 1
            for line in fragment.textLineFragments {
                let lineStart = line.characterRange.location
                guard lineStart == 0 || Self.isLineBreak(paragraph.character(at: lineStart - 1)) else { continue }
                current += 1
                let bounds = line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                guard bounds.maxY >= visible.minY else { continue }
                // 空の行は、行間を文字の上に分けず行の高さに含めて組むので、ベースラインを下端から求める
                let isEmpty = lineStart == paragraph.length || Self.isLineBreak(paragraph.character(at: lineStart))
                let baseline = isEmpty ? bounds.maxY + bodyFont.descender : bounds.minY + line.glyphOrigin.y
                drawNumber(current, baseline: baseline, bodyFont: bodyFont)
            }
            number = current
            return true
        }
    }

    private func lineNumber(at location: Int, in string: NSString) -> Int {
        let number = if let anchor, anchor.location <= location {
            anchor.number + Self.lineBreakCount(
                in: string,
                range: NSRange(location: anchor.location, length: location - anchor.location)
            )
        } else if let anchor {
            anchor.number - Self.lineBreakCount(
                in: string,
                range: NSRange(location: location, length: anchor.location - location)
            )
        } else {
            Self.lineBreakCount(in: string, range: NSRange(location: 0, length: location)) + 1
        }
        anchor = (location, number)
        return number
    }

    /// 空の文書にはレイアウトフラグメントがないので、カーソルの位置から求める
    private func drawEmptyDocumentNumber(
        layoutManager: NSTextLayoutManager,
        at location: any NSTextLocation,
        origin: CGPoint,
        font bodyFont: NSFont
    ) {
        guard let range = NSTextRange(location: location, end: location) else { return }
        layoutManager.enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
            drawNumber(1, baseline: frame.maxY + origin.y + bodyFont.descender, bodyFont: bodyFont)
            return false
        }
    }

    /// 数字の高さの中央を、本文の行の高さの中央に揃える
    private func drawNumber(_ number: Int, baseline: CGFloat, bodyFont: NSFont) {
        let string = String(number) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let width = string.size(withAttributes: attributes).width
        // 計算どおりに中央へ揃えると下がって見えるので、0.5pt上げる
        let middle = baseline - (bodyFont.ascender + bodyFont.descender) / 2 - 0.5
        let point = convert(CGPoint(x: 0, y: middle + font.capHeight / 2 - font.ascender), from: textView)
        string.draw(at: CGPoint(x: (bounds.width - width) / 2, y: point.y), withAttributes: attributes)
    }
}
