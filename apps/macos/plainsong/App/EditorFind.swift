import AppKit

/// 検索のパネルがキーウインドウになっていても、メニューの操作はメインウインドウのコントローラに届く。そのため、常にメインウインドウのテキストを検索する
extension EditorWindowController: NSMenuItemValidation {
    @objc func showFindPanel(_: Any?) {
        FindPanelController.shared.show(for: self, mode: .find)
    }

    @objc func showReplacePanel(_: Any?) {
        FindPanelController.shared.show(for: self, mode: .replace)
    }

    @objc func findNextResult(_: Any?) {
        FindPanelController.shared.move(in: self, backwards: false)
    }

    @objc func findPreviousResult(_: Any?) {
        FindPanelController.shared.move(in: self, backwards: true)
    }

    @objc func selectAllResults(_: Any?) {
        FindPanelController.shared.selectAllResults(in: self)
    }

    @objc func replaceAllResults(_: Any?) {
        FindPanelController.shared.replaceAll(in: self)
    }

    @objc func useSelectionForFind(_: Any?) {
        FindPanelController.shared.useSelection(of: self, forReplacement: false)
    }

    @objc func useSelectionForReplace(_: Any?) {
        FindPanelController.shared.useSelection(of: self, forReplacement: true)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(findNextResult(_:)), #selector(findPreviousResult(_:)), #selector(selectAllResults(_:)):
            FindPanelController.shared.hasPattern
        case #selector(replaceAllResults(_:)):
            FindPanelController.shared.canReplaceAll
        case #selector(useSelectionForFind(_:)), #selector(useSelectionForReplace(_:)):
            textView.selectedRange().length > 0
        default:
            true
        }
    }
}

extension EditorWindowController {
    /// コピーを作らず、テキストストレージの文字列をそのまま返す。テキストを書き換えると、中身も変わる
    var findString: NSString {
        textView.textStorage?.mutableString ?? ""
    }

    var findSelection: NSRange {
        textView.selectedRange()
    }

    var findBackground: NSColor {
        scrollView.backgroundColor
    }

    func setFindSelection(_ range: NSRange) {
        textView.setSelectedRange(range)
    }

    func showFindResult(_ range: NSRange, avoiding panelFrame: NSRect?) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if let panelFrame {
            let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            if rect.intersects(panelFrame) {
                let clipView = scrollView.contentView
                var bounds = clipView.bounds
                bounds.origin.y += rect.maxY - panelFrame.minY + rect.height
                clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
                scrollView.reflectScrolledClipView(clipView)
            }
        }
        if range.length > 0 {
            textView.showFindIndicator(for: range)
        }
    }

    /// 印はテキストの属性ではなくレンダリング属性で描くので、TextStoreは記録せず、取り消しの履歴にも入らない
    func updateFindMarks(
        removing previous: [NSRange],
        results: [NSRange],
        replaced: [NSRange]
    ) -> [NSRange] {
        guard let layoutManager = textView.textLayoutManager else { return [] }
        for range in previous {
            guard let textRange = layoutManager.textRange(for: range) else { continue }
            for key in [NSAttributedString.Key.backgroundColor, .underlineStyle, .underlineColor] {
                layoutManager.removeRenderingAttribute(key, for: textRange)
            }
        }
        let selection = textView.selectedTextAttributes[.backgroundColor] as? NSColor ?? .selectedTextBackgroundColor
        var marked: [NSRange] = []
        func mark(_ range: NSRange, _ attributes: [NSAttributedString.Key: Any]) {
            guard range.length > 0, let textRange = layoutManager.textRange(for: range) else { return }
            for (key, value) in attributes {
                layoutManager.addRenderingAttribute(key, value: value, for: textRange)
            }
            marked.append(range)
        }
        for range in results {
            mark(range, [.backgroundColor: selection.withAlphaComponent(0.45)])
        }
        for range in replaced {
            mark(range, [
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
                .underlineColor: textView.insertionPointColor ?? .textInsertionPointColor,
            ])
        }
        if !previous.isEmpty || !marked.isEmpty {
            redrawText()
        }
        return marked
    }

    func replaceFindResults(_ ranges: [NSRange], with strings: [String], actionName: String) -> [NSRange]? {
        guard let storage = textView.textStorage, !ranges.isEmpty else { return nil }
        textView.discardMarkedTextIfNeeded()
        let strings = strings.map(lineEnding.normalizing)
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: strings)
        else { return nil }
        storage.beginEditing()
        for (range, string) in zip(ranges, strings).reversed() {
            storage.replaceCharacters(in: range, with: string)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        textView.breakUndoCoalescing()
        var offset = 0
        return zip(ranges, strings).map { range, string in
            let length = (string as NSString).length
            defer { offset += length - range.length }
            return NSRange(location: range.location + offset, length: length)
        }
    }

    func selectFindResults(_ ranges: [NSRange]) {
        guard let first = ranges.first else { return }
        textView.selectedRanges = ranges.map { NSValue(range: $0) }
        textView.scrollRangeToVisible(first)
    }
}

extension NSTextLayoutManager {
    func textRange(for range: NSRange) -> NSTextRange? {
        guard let contentManager = textContentManager,
              let start = contentManager.location(documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
