import AppKit

extension EditorWindowController: NSTextViewDelegate {
    func textView(
        _: NSTextView,
        shouldChangeTypingAttributes _: [String: Any],
        toAttributes attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        markdownHighlighter.plainAttributes(typesetter.plainAttributes(attributes))
    }

    /// NSTextViewは、改行キーでいつも\nを入れる
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard lineEnding != .lf,
              selector == #selector(NSResponder.insertNewline(_:))
              || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        else { return false }
        textView.insertText(lineEnding.rawValue, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    /// 状態の復元で後ろに開いたウィンドウでは気づけないので、ウィンドウがキーになるまで待つ
    func noticeMixedLineEndings() {
        needsMixedLineEndingNotice = true
        presentMixedLineEndingNoticeIfNeeded()
    }

    func windowDidBecomeKey(_: Notification) {
        presentMixedLineEndingNoticeIfNeeded()
    }

    private func presentMixedLineEndingNoticeIfNeeded() {
        guard needsMixedLineEndingNotice, let window, window.isKeyWindow, window.attachedSheet == nil else { return }
        needsMixedLineEndingNotice = false
        let suppressionKey = "suppressesMixedLineEndingNotice"
        guard !UserDefaults.standard.bool(forKey: suppressionKey) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.mixedLineEndings.title")
        alert.informativeText = String(localized: "alert.mixedLineEndings.message \(lineEnding.name)")
        alert.showsSuppressionButton = true
        alert.beginSheetModal(for: window) { _ in
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: suppressionKey)
            }
        }
    }
}
