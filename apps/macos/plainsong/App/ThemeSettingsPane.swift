import AppKit

final class ThemeSettingsPane: SettingsPane, NSTableViewDataSource, NSTableViewDelegate {
    private static let listHeight: CGFloat = 300
    private static let headingRowHeight: CGFloat = 11

    private let model: SettingsModel
    private let library = ThemeLibrary()
    private let tableView = ThemeTableView()
    private let importButton = footerButton(symbol: "plus", title: String(localized: "settings.theme.import"))
    private let removeButton = footerButton(symbol: "minus", title: String(localized: "settings.theme.remove"))
    private var rows: [ThemeRow] = []
    /// 一覧を作り直したときの選択の変化で、設定を書き換えないようにする
    private var isReloading = false

    init(model: SettingsModel) {
        self.model = model
        super.init(title: String(localized: "settings.theme"))
    }

    override func makeSections() -> [NSView] {
        let note = Self.note(String(localized: "settings.theme.compatibility"))
        note.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let acknowledgmentsButton = Self.linkButton(
            String(localized: "settings.theme.acknowledgments"),
            target: self,
            action: #selector(showAcknowledgments)
        )
        acknowledgmentsButton.font = note.font
        let footer = NSStackView()
        footer.addView(note, in: .leading)
        footer.addView(acknowledgmentsButton, in: .trailing)
        footer.alignment = .firstBaseline
        footer.spacing = 8
        let section = GroupSection(title: nil, content: makeList(), footer: [footer])
        footer.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return [section]
    }

    private func makeList() -> NSView {
        let column = NSTableColumn()
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28
        tableView.allowsEmptySelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.setAccessibilityLabel(String(localized: "settings.theme"))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.removeSelectedRow = { [weak self] in
            self?.removeSelectedTheme()
        }
        tableView.registerForDraggedTypes([.fileURL])

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        importButton.target = self
        importButton.action = #selector(showOpenPanel)
        removeButton.target = self
        removeButton.action = #selector(removeSelectedTheme)
        let divider = NSBox()
        divider.boxType = .separator
        divider.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let buttons = NSStackView(views: [importButton, divider, removeButton])
        buttons.spacing = 0
        reload()

        let separator = Self.separator()
        let view = NSView()
        for subview in [scrollView, separator, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: Self.listHeight),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: separator.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }

    private func reload() {
        let bundled = library.bundledNames.map { ThemeRow(reference: .bundled($0), library: library) }
        let imported = library.importedNames.map { ThemeRow(reference: .imported($0), library: library) }
        rows = [ThemeRow(reference: .standard, library: library)] + bundled
            + (imported.isEmpty ? [] : [.importedHeading] + imported)
        let row = rows.firstIndex { $0.reference == model.settings.theme } ?? 0
        isReloading = true
        tableView.reloadData()
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        isReloading = false
        // ウィンドウに置く前は表の大きさが決まっておらず、先頭の行が隠れる位置までスクロールしてしまう
        if isViewLoaded, view.window != nil {
            tableView.scrollRowToVisible(row)
        }
        updateRemoveButton()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        tableView.scrollRowToVisible(tableView.selectedRow)
    }

    private var selectedImportedName: String? {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case let .imported(name)? = rows[row].reference else { return nil }
        return name
    }

    private func updateRemoveButton() {
        removeButton.isEnabled = selectedImportedName != nil
    }

    func numberOfRows(in _: NSTableView) -> Int {
        rows.count
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].reference != nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rows[row].reference == nil ? Self.headingRowHeight : tableView.rowHeight
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case let .theme(_, name, theme): ThemeCell(name: name, theme: theme)
        case .importedHeading: ImportedHeadingCell()
        }
    }

    func tableViewSelectionDidChange(_: Notification) {
        updateRemoveButton()
        let row = tableView.selectedRow
        guard !isReloading, rows.indices.contains(row), let reference = rows[row].reference else { return }
        model.update { $0.theme = reference }
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow _: Int,
        proposedDropOperation _: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard !Self.fileURLs(in: info).isEmpty else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(
        _: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row _: Int,
        dropOperation _: NSTableView.DropOperation
    ) -> Bool {
        let urls = Self.fileURLs(in: info)
        guard !urls.isEmpty else { return false }
        importThemes(from: urls)
        return true
    }

    private static func fileURLs(in info: any NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return objects as? [URL] ?? []
    }

    private static func footerButton(symbol: String, title: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
    }

    /// 内蔵のテーマを入れ替えたら、`ThemeLicenses.txt`とあわせて直す
    private static let themeAuthors = [
        (theme: "Catppuccin", author: "Catppuccin", url: "https://github.com/catppuccin/catppuccin"),
        (theme: "Flexoki", author: "Steph Ango", url: "https://github.com/kepano/flexoki"),
        (theme: "GitHub", author: "Primer", url: "https://github.com/primer/github-vscode-theme"),
        (theme: "Iceberg", author: "cocopon", url: "https://github.com/cocopon/iceberg.vim"),
        (theme: "Solarized", author: "Ethan Schoonover", url: "https://github.com/altercation/solarized"),
    ]
    private static let themeSource = (
        name: "iTerm2-Color-Schemes",
        url: "https://github.com/mbadolato/iTerm2-Color-Schemes"
    )

    @objc private func showAcknowledgments() {
        guard let window = view.window else { return }
        let title = String(localized: "settings.theme.acknowledgments")
        SettingsSheetController(title: title, content: Self.acknowledgments(title: title)).begin(for: window)
    }

    private static func acknowledgments(title: String) -> NSTextView {
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacing = 6
        let heading = NSAttributedString(string: title, attributes: body.merging([
            .font: NSFont.preferredFont(forTextStyle: .headline),
            .paragraphStyle: headingStyle,
        ]) { $1 })
        let message = NSAttributedString(
            string: String(localized: "settings.theme.acknowledgments.message"),
            attributes: body
        )
        let blockStyle = NSMutableParagraphStyle()
        blockStyle.paragraphSpacingBefore = 12
        let blockStart = body.merging([.paragraphStyle: blockStyle]) { $1 }
        let authors = themeAuthors.enumerated().map { index, entry in
            let line = NSMutableAttributedString(
                string: "\(entry.theme) — \(entry.author)",
                attributes: index == 0 ? blockStart : body
            )
            line.addAttribute(.link, value: entry.url, range: NSRange(location: 0, length: entry.theme.utf16.count))
            return line
        }
        let source = NSMutableAttributedString(
            string: String(localized: "settings.theme.acknowledgments.source \(themeSource.name)"),
            attributes: blockStart
        )
        let sourceRange = (source.string as NSString).range(of: themeSource.name)
        source.addAttribute(.link, value: themeSource.url, range: sourceRange)

        let text = NSMutableAttributedString()
        for (index, paragraph) in ([heading, message] + authors + [source]).enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "\n", attributes: body))
            }
            text.append(paragraph)
        }

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 0))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: textView.frame.width, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(text)
        textView.sizeToFit()
        NSLayoutConstraint.activate([
            textView.widthAnchor.constraint(equalToConstant: textView.frame.width),
            textView.heightAnchor.constraint(equalToConstant: textView.frame.height),
        ])
        return textView
    }

    /// テーマのファイルには拡張子がないので、種類で絞らない
    @objc private func showOpenPanel() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "settings.theme.import.prompt")
        Task {
            guard await panel.beginSheetModal(for: window) == .OK else { return }
            importThemes(from: panel.urls)
        }
    }

    private func importThemes(from urls: [URL]) {
        var lastImported: String?
        var failures: [String] = []
        for url in urls {
            do {
                lastImported = try library.importTheme(from: url)
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        if let lastImported {
            model.update { $0.theme = .imported(lastImported) }
        }
        reload()
        guard !failures.isEmpty, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "settings.theme.importFailed")
        alert.informativeText = String(
            localized: "settings.theme.importFailed.detail \(failures.formatted(.list(type: .and)))"
        )
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    @objc private func removeSelectedTheme() {
        guard let name = selectedImportedName else { return }
        do {
            try library.removeImported(name)
        } catch {
            if let window = view.window {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
            return
        }
        model.update { $0.theme = .standard }
        reload()
    }
}

private enum ThemeRow {
    case theme(ThemeReference, name: String, theme: Theme?)
    case importedHeading

    init(reference: ThemeReference, library: ThemeLibrary) {
        switch reference {
        case .standard:
            self = .theme(reference, name: String(localized: "settings.theme.standard"), theme: nil)
        case let .bundled(name), let .imported(name):
            self = .theme(reference, name: name, theme: library.theme(for: reference))
        }
    }

    var reference: ThemeReference? {
        switch self {
        case let .theme(reference, _, _): reference
        case .importedHeading: nil
        }
    }
}

private final class ThemeTableView: NSTableView {
    var removeSelectedRow: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch (modifiers, event.specialKey) {
        case ([], .delete?), ([], .deleteForward?): removeSelectedRow()
        default: super.keyDown(with: event)
        }
    }
}

private final class ThemeCell: NSTableCellView {
    init(name: String, theme: Theme?) {
        super.init(frame: .zero)
        let swatch = ThemeSwatch(theme: theme)
        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        textField = label
        for view in [swatch, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }
}

private final class ThemeSwatch: NSView {
    private static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)

    private let theme: Theme?

    init(theme: Theme?) {
        self.theme = theme
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 36, height: 22)
    }

    override func draw(_: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if let theme {
            drawSample(
                background: theme.background ?? .textBackgroundColor,
                text: theme.foreground ?? .textColor,
                cursor: theme.cursor ?? .textInsertionPointColor
            )
        } else {
            let (light, dark) = bounds.divided(atDistance: bounds.width / 2, from: .minXEdge)
            for (half, appearance) in [(light, NSAppearance.Name.aqua), (dark, .darkAqua)] {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: half).addClip()
                NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                    drawSample(background: .textBackgroundColor, text: .textColor, cursor: .textInsertionPointColor)
                }
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.15).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawSample(background: NSColor, text: NSColor, cursor: NSColor) {
        background.setFill()
        bounds.fill()
        let sample = NSAttributedString(string: "Aa", attributes: [.font: Self.font, .foregroundColor: text])
        let size = sample.size()
        let cursorSize = NSSize(width: 1.5, height: 12)
        let gap: CGFloat = 1
        let originX = bounds.midX - (size.width + gap + cursorSize.width) / 2
        sample.draw(at: NSPoint(x: originX, y: bounds.midY - size.height / 2))
        cursor.setFill()
        NSRect(
            x: originX + size.width + gap,
            y: bounds.midY - cursorSize.height / 2,
            width: cursorSize.width,
            height: cursorSize.height
        ).fill()
    }
}

private final class ImportedHeadingCell: NSTableCellView {
    init() {
        super.init(frame: .zero)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(String(localized: "settings.theme.imported"))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }
}
