import AppKit

extension EditorWindowController {
    /// applyFont(of:)とapplyTheme(_:)が本文全体に指定した属性
    private static let formattingKeys: [NSAttributedString.Key] = [.font, .paragraphStyle, .foregroundColor]
    private static let unstyledFormattingKeys = formattingKeys.filter { !MarkdownHighlighter.styledKeys.contains($0) }

    @objc func undoManagerDidChange(_ notification: Notification) {
        guard let undoManager = (document as? NSDocument)?.undoManager,
              notification.object as? UndoManager === undoManager
        else { return }
        normalizeFormatting()
    }

    /// 取り消しとやり直しは、消した時点の属性ごと文字を戻すので、そのあとに設定を変えていたら、今の書式に直す
    /// 属性の変更なので、TextStoreは記録せず、取り消しの履歴にも入らない
    /// 記法で変えたフォントと色は、戻った文字を`MarkdownHighlighter`が読み直して付け直すので、ここでは直さない
    private func normalizeFormatting() {
        // 変換中は、入力する文字の属性が設定の書式と異なることがある
        guard !textView.hasMarkedText(), let storage = textView.textStorage, storage.length > 0 else { return }
        let current = textView.typingAttributes
        var staleRanges: [(range: NSRange, keys: [NSAttributedString.Key])] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            var keys = attributes[.markdownStyle] == nil ? Self.formattingKeys : Self.unstyledFormattingKeys
            if attributes[.uprightOriginalFont] != nil, let index = keys.firstIndex(of: .font) {
                keys[index] = .uprightOriginalFont
            }
            let isStale = keys.contains { key in
                attributes[key] as? NSObject != current[Self.typingKey(for: key)] as? NSObject
            }
            if isStale {
                staleRanges.append((range, keys))
            }
        }
        guard !staleRanges.isEmpty else { return }
        storage.beginEditing()
        for (range, keys) in staleRanges {
            for key in keys {
                if let value = current[Self.typingKey(for: key)] {
                    storage.addAttribute(key, value: value, range: range)
                } else {
                    storage.removeAttribute(key, range: range)
                }
            }
        }
        storage.endEditing()
    }

    private static func typingKey(for key: NSAttributedString.Key) -> NSAttributedString.Key {
        key == .uprightOriginalFont ? .font : key
    }
}
