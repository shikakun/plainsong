import AppKit

final class ExtensionItemList: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    struct Row {
        let title: String
        let summary: String
        let symbol: String?
        let hasOptions: Bool
        let isEnabled: Bool

        init(_ item: ExtensionItem<some ExtensionItemKind>) {
            title = item.kind.title
            summary = item.kind.summary
            symbol = item.kind.symbol
            hasOptions = item.kind.hasOptions
            isEnabled = item.isEnabled
        }
    }

    private static let itemType = NSPasteboard.PasteboardType("com.shikakun.plainsong.extension-item")

    let view = NSScrollView()
    private let tableView = ExtensionItemTableView()
    private let height: NSLayoutConstraint
    private let rows: () -> [Row]
    private let onMove: (_ source: Int, _ destination: Int) -> Void
    private let onToggle: (_ row: Int, _ isEnabled: Bool) -> Void
    private let onShowOptions: (_ row: Int) -> Void

    init(
        title: String,
        rows: @escaping () -> [Row],
        onMove: @escaping (Int, Int) -> Void,
        onToggle: @escaping (Int, Bool) -> Void,
        onShowOptions: @escaping (Int) -> Void = { _ in }
    ) {
        self.rows = rows
        self.onMove = onMove
        self.onToggle = onToggle
        self.onShowOptions = onShowOptions
        height = view.heightAnchor.constraint(equalToConstant: 0)
        super.init()

        let column = NSTableColumn()
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.usesAutomaticRowHeights = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.setAccessibilityLabel(title)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = makeMoveMenu()
        tableView.moveSelectedRow = { [weak self] move in
            self?.moveSelectedRow(move)
        }
        tableView.toggleSelectedRow = { [weak self] in
            self?.toggleSelectedRow()
        }
        tableView.registerForDraggedTypes([Self.itemType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.reloadData()

        view.documentView = tableView
        view.drawsBackground = false
        view.verticalScrollElasticity = .none
        height.constant = tableView.intrinsicContentSize.height
        height.isActive = true
    }

    /// 行の高さは説明文の折り返しで変わり、ウィンドウに置いて幅が決まるまでわからない。幅が決まったら合わせ直し、高さが変わったかを返す
    func fitHeight() -> Bool {
        let height = tableView.intrinsicContentSize.height
        guard self.height.constant != height else { return false }
        self.height.constant = height
        return true
    }

    /// 右クリックで開く。⌥⌘↑と⌥⌘↓は表が受け取るので、メニューに出すのはショートカットを知らせるため
    private func makeMoveMenu() -> NSMenu {
        let menu = NSMenu()
        for move in ExtensionItemMove.allCases {
            if move == .top {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(
                title: move.title,
                action: #selector(moveFromMenu(_:)),
                keyEquivalent: move.key.map { String(Character($0.unicodeScalar)) } ?? ""
            )
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self
            item.tag = move.rawValue
            menu.addItem(item)
        }
        return menu
    }

    func numberOfRows(in _: NSTableView) -> Int {
        rows().count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let cell = ExtensionItemCell(row: rows()[row])
        cell.toggle.target = self
        cell.toggle.action = #selector(toggleItem(_:))
        cell.optionsButton?.target = self
        cell.optionsButton?.action = #selector(showOptions(_:))
        cell.moveActions = { [weak self, weak tableView, weak cell] in
            guard let self, let tableView, let cell else { return [] }
            return moveActions(for: tableView.row(for: cell))
        }
        return cell
    }

    func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.itemType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(
        _: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation _: NSTableView.DropOperation
    ) -> Bool {
        guard let source = info.draggingPasteboard.pasteboardItems?.first?
            .string(forType: Self.itemType).flatMap(Int.init)
        else { return false }
        // ドラッグした行より下に落とすと、その行が抜けた分だけ位置がずれる
        let destination = source < row ? row - 1 : row
        guard source != destination else { return false }
        moveItem(from: source, to: destination)
        return true
    }

    private func moveItem(from source: Int, to destination: Int) {
        guard source != destination else { return }
        onMove(source, destination)
        tableView.moveRow(at: source, to: destination)
    }

    private func destination(of move: ExtensionItemMove, from row: Int) -> Int {
        let last = rows().count - 1
        return switch move {
        case .up: max(row - 1, 0)
        case .down: min(row + 1, last)
        case .top: 0
        case .bottom: last
        }
    }

    private func moveSelectedRow(_ move: ExtensionItemMove) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        moveItem(from: row, to: destination(of: move, from: row))
    }

    private func toggleSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ExtensionItemCell)?.toggle.performClick(nil)
    }

    private var menuRow: Int? {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        return row >= 0 ? row : nil
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let move = ExtensionItemMove(rawValue: menuItem.tag), let row = menuRow else { return false }
        return destination(of: move, from: row) != row
    }

    @objc private func moveFromMenu(_ sender: NSMenuItem) {
        guard let move = ExtensionItemMove(rawValue: sender.tag), let row = menuRow else { return }
        moveItem(from: row, to: destination(of: move, from: row))
    }

    private func moveActions(for row: Int) -> [NSAccessibilityCustomAction] {
        guard row >= 0 else { return [] }
        var actions: [NSAccessibilityCustomAction] = []
        if row > 0 {
            actions.append(NSAccessibilityCustomAction(name: String(localized: "settings.moveUp")) { [weak self] in
                self?.moveItem(from: row, to: row - 1)
                return true
            })
        }
        if row < rows().count - 1 {
            actions.append(NSAccessibilityCustomAction(name: String(localized: "settings.moveDown")) { [weak self] in
                self?.moveItem(from: row, to: row + 1)
                return true
            })
        }
        return actions
    }

    @objc private func toggleItem(_ sender: NSSwitch) {
        let row = tableView.row(for: sender)
        guard row >= 0 else { return }
        onToggle(row, sender.state == .on)
    }

    @objc private func showOptions(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 else { return }
        onShowOptions(row)
    }
}

private enum ExtensionItemMove: Int, CaseIterable {
    case up
    case down
    case top
    case bottom

    var title: String {
        switch self {
        case .up: String(localized: "settings.moveUp")
        case .down: String(localized: "settings.moveDown")
        case .top: String(localized: "settings.moveToTop")
        case .bottom: String(localized: "settings.moveToBottom")
        }
    }

    var key: NSEvent.SpecialKey? {
        switch self {
        case .up: .upArrow
        case .down: .downArrow
        case .top, .bottom: nil
        }
    }
}

private final class ExtensionItemTableView: NSTableView {
    var moveSelectedRow: (ExtensionItemMove) -> Void = { _ in }
    var toggleSelectedRow: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch (modifiers, event.specialKey) {
        case ([.command, .option], .upArrow?): moveSelectedRow(.up)
        case ([.command, .option], .downArrow?): moveSelectedRow(.down)
        case ([], nil) where event.charactersIgnoringModifiers == " ": toggleSelectedRow()
        default: super.keyDown(with: event)
        }
    }
}

private final class ExtensionItemCell: NSTableCellView {
    private static let padding: CGFloat = 8
    private static let spacing: CGFloat = 8

    let toggle = NSSwitch()
    let optionsButton: NSButton?
    var moveActions: () -> [NSAccessibilityCustomAction] = { [] }

    init(row: ExtensionItemList.Row) {
        optionsButton = row.hasOptions
            ? NSButton(title: String(localized: "settings.options"), target: nil, action: nil)
            : nil
        super.init(frame: .zero)
        let grip = Self.symbol("line.3.horizontal", color: .tertiaryLabelColor)
        let icon = row.symbol.map { Self.symbol($0, color: .secondaryLabelColor) }
        let title = NSTextField(wrappingLabelWithString: row.title)
        let summary = NSTextField(wrappingLabelWithString: row.summary)
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.textColor = .secondaryLabelColor
        toggle.controlSize = .mini
        toggle.state = row.isEnabled ? .on : .off
        toggle.setAccessibilityLabel(row.title)
        toggle.setAccessibilityHelp(row.summary)
        optionsButton?.controlSize = .small
        optionsButton?.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let leading = [grip, icon].compactMap(\.self)
        let controls = [optionsButton, toggle].compactMap(\.self)
        for view in leading + [title, summary] + controls {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for view in leading + controls {
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
        let firstLineCenter = NSLayoutManager().defaultLineHeight(for: title.font ?? .systemFont(ofSize: 0)) / 2
        var constraints = [
            grip.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.leadingAnchor.constraint(equalTo: (icon ?? grip).trailingAnchor, constant: Self.spacing),
            title.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            summary.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            summary.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        if let icon {
            constraints.append(icon.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: Self.spacing))
        }
        for view in leading + controls {
            constraints += [
                view.centerYAnchor.constraint(equalTo: title.topAnchor, constant: firstLineCenter),
                view.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Self.padding),
            ]
        }
        let gap = -Self.spacing
        for label in [title, summary] {
            constraints.append(label.trailingAnchor.constraint(equalTo: controls[0].leadingAnchor, constant: gap))
        }
        if let optionsButton {
            constraints.append(optionsButton.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: gap))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private static func symbol(_ name: String, color: NSColor) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.contentTintColor = color
        view.setAccessibilityElement(false)
        return view
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        moveActions()
    }
}
