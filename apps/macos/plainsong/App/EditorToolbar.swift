import AppKit

final class EditorToolbar: NSObject, NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate {
    let kinds: [ToolbarItemKind]
    let toolbar = NSToolbar(identifier: "Editor")
    var kindsIgnoringSelection: Set<ToolbarItemKind> = []
    var findOpensReplace = false
    private weak var textView: NSTextView?

    init(kinds: [ToolbarItemKind], textView: NSTextView) {
        self.kinds = kinds
        self.textView = textView
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + kinds.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        guard let kind = ToolbarItemKind(rawValue: identifier.rawValue) else { return nil }
        let item: NSToolbarItem
        if kind == .share {
            let picker = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            picker.delegate = self
            item = picker
        } else {
            item = NSToolbarItem(itemIdentifier: identifier)
            item.image = kind.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            item.isBordered = true
            switch kind {
            case .copy:
                item.target = self
                item.action = #selector(copyText(_:))
            case .find:
                item.target = self
                item.action = #selector(findText(_:))
            case .save:
                item.action = #selector(NSDocument.save(_:))
            case .delete:
                item.target = self
                item.action = #selector(deleteText(_:))
            case .share:
                break
            }
        }
        item.label = kind.title
        item.toolTip = kind.title
        return item
    }

    func items(for _: NSSharingServicePickerToolbarItem) -> [Any] {
        guard let textView else { return [] }
        return [targetText(of: textView, for: .share)]
    }

    @objc private func copyText(_: Any?) {
        guard let textView else { return }
        if selectedRanges(of: textView, for: .copy).isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(textView.string, forType: .string)
        } else {
            textView.copy(nil)
        }
        announce(String(localized: "toolbarItem.copy.done"))
    }

    @objc private func findText(_: Any?) {
        guard let textView, let editor = textView.window?.windowController as? EditorWindowController else { return }
        if !selectedRanges(of: textView, for: .find).isEmpty {
            editor.useSelectionForFind(nil)
        }
        if findOpensReplace {
            editor.showReplacePanel(nil)
        } else {
            editor.showFindPanel(nil)
        }
    }

    /// 全文を消すときも⌘Zで取り消せるよう、キー入力と同じ手順で書き換える
    @objc private func deleteText(_: Any?) {
        guard let textView else { return }
        textView.discardMarkedTextIfNeeded()
        if selectedRanges(of: textView, for: .delete).isEmpty {
            let range = NSRange(location: 0, length: (textView.string as NSString).length)
            guard textView.shouldChangeText(in: range, replacementString: "") else { return }
            textView.replaceCharacters(in: range, with: "")
            textView.didChangeText()
        } else {
            textView.delete(nil)
        }
        announce(String(localized: "toolbarItem.delete.done"))
    }

    private func selectedRanges(of textView: NSTextView, for kind: ToolbarItemKind) -> [NSRange] {
        guard !kindsIgnoringSelection.contains(kind) else { return [] }
        return textView.nonEmptySelectedRanges
    }

    private func targetText(of textView: NSTextView, for kind: ToolbarItemKind) -> String {
        let ranges = selectedRanges(of: textView, for: kind)
        guard !ranges.isEmpty else { return textView.string }
        let string = textView.string as NSString
        return ranges.map { string.substring(with: $0) }.joined(separator: "\n")
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
