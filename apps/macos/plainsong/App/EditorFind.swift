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

    func showFindResult(_ range: NSRange, avoiding panel: NSWindow?) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if let panel {
            uncoverFindResult(range, under: panel)
        }
        if range.length > 0 {
            textView.showFindIndicator(for: range)
        }
    }

    /// 文書の端にある結果はスクロールしても動かせないので、パネルのほうを動かす
    private func uncoverFindResult(_ range: NSRange, under panel: NSWindow) {
        let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        guard rect.intersects(panel.frame), let window else { return }
        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let isVertical = textView.layoutOrientation == .vertical
        let visible = window.convertToScreen(window.contentLayoutRect)
        let shifts = isVertical
            ? Self.shifts(rect.minX ... rect.maxX, clearing: panel.frame.minX ... panel.frame.maxX, margin: rect.width)
            : Self.shifts(rect.minY ... rect.maxY, clearing: panel.frame.minY ... panel.frame.maxY, margin: rect.height)
        for shift in shifts {
            var bounds = clipView.bounds
            if isVertical {
                bounds.origin.x -= shift
            } else {
                bounds.origin.y += shift
            }
            let target = clipView.constrainBoundsRect(bounds).origin
            let moved = isVertical
                ? rect.offsetBy(dx: origin.x - target.x, dy: 0)
                : rect.offsetBy(dx: 0, dy: target.y - origin.y)
            if !moved.intersects(panel.frame), visible.contains(moved) {
                clipView.scroll(to: target)
                scrollView.reflectScrolledClipView(clipView)
                return
            }
        }
        let screen = (panel.screen ?? window.screen)?.visibleFrame ?? .infinite
        let frames = Self.shifts(panel.frame.minX ... panel.frame.maxX, clearing: rect.minX ... rect.maxX, margin: 0)
            .map { (distance: abs($0), frame: panel.frame.offsetBy(dx: $0, dy: 0)) }
            + Self.shifts(panel.frame.minY ... panel.frame.maxY, clearing: rect.minY ... rect.maxY, margin: 0)
            .map { (distance: abs($0), frame: panel.frame.offsetBy(dx: 0, dy: $0)) }
        if let frame = frames.filter({ screen.contains($0.frame) }).min(by: { $0.distance < $1.distance })?.frame {
            panel.setFrameOrigin(frame.origin)
        }
    }

    private static func shifts(
        _ covered: ClosedRange<CGFloat>,
        clearing cover: ClosedRange<CGFloat>,
        margin: CGFloat
    ) -> [CGFloat] {
        [cover.lowerBound - covered.upperBound - margin, cover.upperBound - covered.lowerBound + margin]
            .sorted { abs($0) < abs($1) }
    }

    /// 印はテキストの属性にしないので、TextStoreは記録せず、取り消しの履歴にも入らない
    /// TextKit 2は描画用の属性の下線を描かないので、置換した箇所の下線はレイアウトフラグメントで描く
    func updateFindMarks(
        removing previous: [NSRange],
        results: [NSRange],
        replaced: [NSRange]
    ) -> [NSRange] {
        guard let layoutManager = textView.textLayoutManager else { return [] }
        for range in previous {
            guard let textRange = layoutManager.textRange(for: range) else { continue }
            layoutManager.removeRenderingAttribute(.backgroundColor, for: textRange)
        }
        let selection = textView.selectedTextAttributes[.backgroundColor] as? NSColor ?? .selectedTextBackgroundColor
        let marked = results.filter { range in
            guard range.length > 0, let textRange = layoutManager.textRange(for: range) else { return false }
            layoutManager.addRenderingAttribute(
                .backgroundColor,
                value: selection.withAlphaComponent(0.45),
                for: textRange
            )
            return true
        }
        let replaced = replaced.filter { $0.length > 0 }
        let replacedChanged = replaced != whitespaceMarkers.replacedRanges
        whitespaceMarkers.replacedRanges = replaced
        whitespaceMarkers.replacedColor = textView.insertionPointColor ?? .textInsertionPointColor
        if !previous.isEmpty || !marked.isEmpty || replacedChanged {
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
