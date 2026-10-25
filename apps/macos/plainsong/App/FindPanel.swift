import AppKit

final class FindPanel: NSPanel, NSToolbarDelegate {
    enum Mode: Int {
        case find
        case replace
    }

    private static let modeItemIdentifier = NSToolbarItem.Identifier("FindPanelMode")
    private static let iconSize = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)

    let modeControl = NSSegmentedControl(
        labels: [String(localized: "find.mode.find"), String(localized: "find.mode.replace")],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    let findField = NSTextField()
    let replaceField = NSTextField()
    let navigationControl = NSSegmentedControl()
    let matchesCaseButton = FindPanel.checkbox("find.matchesCase")
    let matchesWidthButton = FindPanel.checkbox("find.matchesWidth")
    let regularExpressionButton = FindPanel.checkbox("find.regularExpression")
    let wrapsAroundButton = FindPanel.checkbox("find.wrapsAround")
    let findNextButton = NSButton(title: String(localized: "find.next"), target: nil, action: nil)
    /// 「すべて置換」は一度にまとめて書き換えるので、誤って押さないよう、ボタンのメニューの中に入れる
    let replaceAllItem = NSMenuItem(title: String(localized: "find.replaceAll"), action: nil, keyEquivalent: "")
    let replaceAndFindButton = NSComboButton()
    private let countLabel = NSTextField(labelWithString: "")
    private let warningIcon = NSImageView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let statusIcon = NSImageView()
    private let status = NSStackView()
    private let findLabel = NSTextField(labelWithString: String(localized: "find.label.find"))
    private let replaceLabel = NSTextField(labelWithString: String(localized: "find.label.replace"))
    private let grid = NSGridView()

    var mode = Mode.find {
        didSet { applyMode() }
    }

    private var replaceRow: NSGridRow {
        grid.row(at: 1)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        // タイトルは画面に出さないが、VoiceOverの読み上げとウインドウメニューに使われる
        title = String(localized: "find.panel.title")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        // NSPanelにするのは、メインウインドウにならないから。それ以外は通常のウインドウと同じに扱う
        isFloatingPanel = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = false
        collectionBehavior = [.fullScreenAuxiliary]
        configureControls()
        layOut()
        let toolbar = NSToolbar(identifier: "FindPanel")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.modeItemIdentifier]
        self.toolbar = toolbar
        toolbarStyle = .unifiedCompact
        applyMode()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    func showCount(_ text: String, isError: Bool = false, accessibilityText: String? = nil) {
        Self.setText(text, of: countLabel, color: .secondaryLabelColor)
        countLabel.toolTip = accessibilityText
        countLabel.setAccessibilityLabel(accessibilityText ?? text)
        warningIcon.isHidden = !isError
    }

    func showStatus(_ outcome: FindOutcome?) {
        Self.setText(outcome?.message ?? "", of: statusLabel, color: .labelColor)
        let isWarning = outcome?.isWarning == true
        let symbol = isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        statusIcon.symbolConfiguration = isWarning ? Self.iconSize.applying(.preferringMulticolor()) : Self.iconSize
        statusIcon.contentTintColor = isWarning ? nil : .systemGreen
        let isHidden = outcome == nil
        guard status.isHidden != isHidden else { return }
        status.isHidden = isHidden
        fitHeight()
    }

    func place(near editorFrame: NSRect?) {
        let name = "FindPanel"
        if !setFrameUsingName(name), let editorFrame {
            layoutIfNeeded()
            setFrameTopLeftPoint(NSPoint(x: editorFrame.maxX - frame.width - 24, y: editorFrame.maxY - 64))
        }
        setFrameAutosaveName(name)
    }

    func announce(_ text: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// テキストのウインドウの見た目に合わせるだけにとどめ、背景を塗り分けたり区切り線を引いたりはしない
    func applyAppearance(of window: NSWindow?, background: NSColor) {
        appearance = window?.appearance
        backgroundColor = background
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.modeItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        guard identifier == Self.modeItemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = modeControl
        item.label = title
        return item
    }

    private static func checkbox(_ title: String.LocalizationValue) -> NSButton {
        NSButton(checkboxWithTitle: String(localized: title), target: nil, action: nil)
    }

    private static func setText(_ text: String, of label: NSTextField, color: NSColor) {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        label.font = font
        label.textColor = color
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            // 0を指定して、数字と漢字のあいだに自動で入る空きを止める
            .kern: 0,
        ])
    }

    private func configureControls() {
        modeControl.setAccessibilityLabel(String(localized: "find.panel.title"))
        findField.setAccessibilityLabel(String(localized: "find.label.find"))
        replaceField.setAccessibilityLabel(String(localized: "find.label.replace"))
        for field in [findField, replaceField] {
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
        }
        navigationControl.segmentCount = 2
        navigationControl.trackingMode = .momentary
        for (segment, key) in [(0, "find.previous"), (1, "find.next")] {
            let title = String(localized: String.LocalizationValue(key))
            let symbol = segment == 0 ? "chevron.left" : "chevron.right"
            navigationControl.setImage(
                NSImage(systemSymbolName: symbol, accessibilityDescription: title),
                forSegment: segment
            )
            navigationControl.setToolTip(title, forSegment: segment)
        }
        warningIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        warningIcon.symbolConfiguration = Self.iconSize.applying(.preferringMulticolor())
        warningIcon.isHidden = true
        // 選択できるラベルは、ポインタを重ねると欄の設定で描き直されるので、文字列の属性を引き継がせないと色と字間が変わる
        statusLabel.allowsEditingTextAttributes = true
        statusIcon.setAccessibilityElement(false)
        statusIcon.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replaceAndFindButton.title = String(localized: "find.replaceAndFind")
        replaceAndFindButton.style = .split
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(replaceAllItem)
        replaceAndFindButton.menu = menu
    }

    private func layOut() {
        let options = NSGridView(views: [
            [matchesCaseButton, matchesWidthButton],
            [regularExpressionButton, wrapsAroundButton],
        ])
        options.rowSpacing = 6
        options.columnSpacing = 12
        let empty = NSGridCell.emptyContentView
        grid.addRow(with: [findLabel, findField])
        grid.addRow(with: [replaceLabel, replaceField])
        grid.addRow(with: [empty, options])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        // 置換の行を隠すとラベルの列が縮んで検索欄がずれるので、2つのラベルのうち広いほうに幅を合わせておく
        let column = grid.column(at: 0)
        column.width = max(findLabel.fittingSize.width, replaceLabel.fittingSize.width)
        column.xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.row(at: 2).topPadding = 2
        grid.row(at: 2).rowAlignment = .none

        let count = NSStackView(views: [warningIcon, countLabel])
        count.spacing = 3
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.detachesHiddenViews = true
        footer.addView(navigationControl, in: .leading)
        footer.addView(count, in: .leading)
        footer.addView(replaceAndFindButton, in: .trailing)
        footer.addView(findNextButton, in: .trailing)

        status.setViews([statusIcon, statusLabel], in: .leading)
        status.alignment = .firstBaseline
        status.spacing = 4
        status.detachesHiddenViews = true

        let stack = NSStackView(views: [grid, footer, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(8, after: footer)
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        let contentView = NSView()
        contentView.addSubview(stack)
        self.contentView = contentView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            // 高さはfitHeight()で中身に合わせる。伸び縮みしている途中の高さと制約がぶつからないよう、下端の余白は広がってもよいことにする
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            grid.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            footer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            status.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 460),
        ])
    }

    private func applyMode() {
        modeControl.selectedSegment = mode.rawValue
        let replaces = mode == .replace
        replaceRow.isHidden = !replaces
        replaceAndFindButton.isHidden = !replaces
        findNextButton.isHidden = replaces
        status.isHidden = statusLabel.stringValue.isEmpty
        fitHeight()
    }

    private func fitHeight() {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let height = contentView.fittingSize.height
        let contentRect = NSRect(origin: .zero, size: NSSize(width: contentView.frame.width, height: height))
        var frame = frameRect(forContentRect: contentRect)
        frame.origin = NSPoint(x: self.frame.minX, y: self.frame.maxY - frame.height)
        setFrame(frame, display: true, animate: isVisible)
    }
}
