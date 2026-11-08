import AppKit

extension EditorSettings {
    enum LineNumberUnit: String, CaseIterable {
        case paragraph
        case line

        var title: String {
            switch self {
            case .paragraph: String(localized: "settings.lineNumberUnit.paragraph")
            case .line: String(localized: "settings.lineNumberUnit.line")
            }
        }
    }
}

/// 本文の行頭の側の余白に重ねる。描くのは見えている行だけ
final class LineNumberView: NSView {
    private let textView: NSTextView
    /// 前回描いたときの、先頭の段落の位置と行番号。そこから数えれば、文書の先頭から数え直さずに済む
    private var anchor: (location: Int, number: Int)?
    /// 行ごとに数えた`anchor`は折り返しで変わるので、数えたときのテキストコンテナの大きさを覚えておく
    private var anchorContainerSize: CGSize?

    var unit = EditorSettings.LineNumberUnit.paragraph {
        didSet {
            guard unit != oldValue else { return }
            anchor = nil
            needsDisplay = true
        }
    }

    private var font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
    }

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
        // 行ごとに数えるときは、フォントなど属性の変更でも折り返しが変わる
        let mask: NSTextStorageEditActions = unit == .line ? [.editedCharacters, .editedAttributes] : .editedCharacters
        guard let anchor, let storage = notification.object as? NSTextStorage,
              !storage.editedMask.isDisjoint(with: mask),
              storage.editedRange.location < anchor.location
        else { return }
        self.anchor = nil
    }

    @objc private func clipViewBoundsDidChange(_: Notification) {
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard let layoutManager = textView.textLayoutManager as? LineHeightSegmentLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let string = textView.textStorage?.mutableString,
              let bodyFont = textView.typingAttributes[.font] as? NSFont
        else { return }
        let isVertical = textView.layoutOrientation == .vertical
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
        // 番号を描きながらそれより前をレイアウトすると、描いている途中で位置がずれるので、先に数える
        if unit == .line {
            number = lineNumber(at: contentManager.offset(from: documentStart, to: start), in: layoutManager) - 1
        }
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
                guard unit == .line || lineStart == 0 || Self.isLineBreak(paragraph.character(at: lineStart - 1))
                else { continue }
                current += 1
                let bounds = line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                guard bounds.maxY >= visible.minY else { continue }
                let isEmpty = lineStart == paragraph.length || Self.isLineBreak(paragraph.character(at: lineStart))
                if isVertical {
                    let middle = layoutManager.verticalMiddle(of: line, in: bounds, isEmpty: isEmpty)
                    drawVerticalNumber(current, middle: middle)
                } else {
                    // 空の行は、行間を文字の上に分けず行の高さに含めて組むので、ベースラインを下端から求める
                    let baseline = isEmpty ? bounds.maxY + bodyFont.descender : bounds.minY + line.glyphOrigin.y
                    drawNumber(current, baseline: baseline, bodyFont: bodyFont)
                }
            }
            number = current
            return true
        }
    }

    private func lineNumber(at location: Int, in string: NSString) -> Int {
        lineNumber(at: location) { range in
            Self.lineBreakCount(in: string, range: range)
        }
    }

    private func lineNumber(at location: Int, in layoutManager: NSTextLayoutManager) -> Int {
        let containerSize = textView.textContainer?.size
        if containerSize != anchorContainerSize {
            anchor = nil
            anchorContainerSize = containerSize
        }
        return lineNumber(at: location) { range in
            Self.lineFragmentCount(in: range, of: layoutManager)
        }
    }

    /// `count`には、段落の先頭から段落の先頭までの範囲を渡す
    private func lineNumber(at location: Int, count: (NSRange) -> Int) -> Int {
        let number = if let anchor, anchor.location <= location {
            anchor.number + count(NSRange(location: anchor.location, length: location - anchor.location))
        } else if let anchor {
            anchor.number - count(NSRange(location: location, length: anchor.location - location))
        } else {
            count(NSRange(location: 0, length: location)) + 1
        }
        anchor = (location, number)
        return number
    }

    private static func lineFragmentCount(in range: NSRange, of layoutManager: NSTextLayoutManager) -> Int {
        guard range.length > 0, let contentManager = layoutManager.textContentManager else { return 0 }
        let documentStart = contentManager.documentRange.location
        guard let start = contentManager.location(documentStart, offsetBy: range.location) else { return 0 }
        var count = 0
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            guard contentManager.offset(from: documentStart, to: fragment.rangeInElement.location) < NSMaxRange(range)
            else { return false }
            count += fragment.textLineFragments.count
            return true
        }
        return count
    }

    /// 空の文書にはレイアウトフラグメントがないので、カーソルの位置から求める
    private func drawEmptyDocumentNumber(
        layoutManager: NSTextLayoutManager,
        at location: any NSTextLocation,
        origin: CGPoint,
        font bodyFont: NSFont
    ) {
        guard let range = NSTextRange(location: location, end: location) else { return }
        layoutManager.enumerateTextSegments(in: range, type: .standard) { _, frame, baseline, _ in
            if textView.layoutOrientation == .vertical {
                drawVerticalNumber(1, middle: frame.minY + baseline + origin.y)
            } else {
                drawNumber(1, baseline: frame.minY + baseline + origin.y, bodyFont: bodyFont)
            }
            return false
        }
    }

    /// 数字の高さの中央を、本文の行の高さの中央に揃える
    private func drawNumber(_ number: Int, baseline: CGFloat, bodyFont: NSFont) {
        let string = String(number) as NSString
        let attributes = attributes
        let width = string.size(withAttributes: attributes).width
        // 計算どおりに中央へ揃えると下がって見えるので、0.5pt上げる
        let middle = baseline - (bodyFont.ascender + bodyFont.descender) / 2 - 0.5
        let point = convert(CGPoint(x: 0, y: middle + font.capHeight / 2 - font.ascender), from: textView)
        string.draw(at: CGPoint(x: (bounds.width - width) / 2, y: point.y), withAttributes: attributes)
    }

    private func drawVerticalNumber(_ number: Int, middle: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let string = String(number) as NSString
        let attributes = attributes
        let width = string.size(withAttributes: attributes).width
        let center = convert(CGPoint(x: 0, y: middle), from: textView).x
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center, y: bounds.midY)
        context.rotate(by: .pi / 2)
        string.draw(at: CGPoint(x: -width / 2, y: font.capHeight / 2 - font.ascender), withAttributes: attributes)
    }
}

final class LineNumberOptions: NSObject {
    private let model: SettingsModel
    let checkbox = NSButton(
        checkboxWithTitle: String(localized: "settings.showsLineNumbers"),
        target: nil,
        action: nil
    )
    let unitButton = NSPopUpButton()

    init(model: SettingsModel) {
        self.model = model
        super.init()
        checkbox.target = self
        checkbox.action = #selector(changeShowsLineNumbers(_:))
        unitButton.addItems(for: EditorSettings.LineNumberUnit.self, title: \.title)
        unitButton.target = self
        unitButton.action = #selector(changeUnit(_:))
        unitButton.setAccessibilityLabel(String(localized: "settings.lineNumberUnit"))
    }

    func update(with settings: EditorSettings) {
        checkbox.state = settings.showsLineNumbers ? .on : .off
        unitButton.selectItem(for: settings.lineNumberUnit)
    }

    @objc private func changeShowsLineNumbers(_ sender: NSButton) {
        model.update { $0.showsLineNumbers = sender.state == .on }
    }

    @objc private func changeUnit(_ sender: NSPopUpButton) {
        guard let unit = sender.selectedCase(of: EditorSettings.LineNumberUnit.self) else { return }
        model.update { $0.lineNumberUnit = unit }
    }
}
