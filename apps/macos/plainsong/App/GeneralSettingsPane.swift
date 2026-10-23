import AppKit

final class GeneralSettingsPane: SettingsPane {
    private let model: SettingsModel
    private let relaunch: () -> Void
    private let fontFamilyButton = NSPopUpButton()
    private let fontSizeSlider = NSSlider()
    private let lineSpacingControl = NSSegmentedControl()
    private let kerningCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.kerning"),
        target: nil,
        action: nil
    )
    private let readableWidthCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.usesReadableWidth"),
        target: nil,
        action: nil
    )
    private let readableWidthButton = NSPopUpButton()
    private var readableWidthRow: NSGridRow?
    private let newlinesCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.showsNewlines"),
        target: nil,
        action: nil
    )
    private let whitespaceCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.showsWhitespace"),
        target: nil,
        action: nil
    )
    private let whitespaceScopeButton = NSPopUpButton()
    private var whitespaceScopeRow: NSGridRow?
    private let lineNumbersCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.showsLineNumbers"),
        target: nil,
        action: nil
    )
    private let paragraphSpacingCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.addsParagraphSpacing"),
        target: nil,
        action: nil
    )
    private let paragraphSpacingButton = NSPopUpButton()
    private var paragraphSpacingRow: NSGridRow?
    private let paragraphIndentCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.indentsParagraphs"),
        target: nil,
        action: nil
    )
    private let paragraphIndentButton = NSPopUpButton()
    private var paragraphIndentRow: NSGridRow?
    private let languageButton = NSPopUpButton()
    private let iconPlacementButton = NSPopUpButton()
    private let fileAutosaveButton = NSPopUpButton()
    private var openBackupsRow: NSGridRow?
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.launchAtLogin"),
        target: nil,
        action: nil
    )
    private var requiresApprovalRow: NSGridRow?

    init(model: SettingsModel, relaunch: @escaping () -> Void) {
        self.model = model
        self.relaunch = relaunch
        super.init(title: String(localized: "settings.general"))
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange(_:)),
            name: SettingsModel.didChangeNotification,
            object: model
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: view.window
        )
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    override func makeSections() -> [NSView] {
        let fontFamily = String(localized: "settings.fontFamily")
        fontFamilyButton.addItems(for: EditorSettings.FontFamily.self, title: \.title)
        fontFamilyButton.target = self
        fontFamilyButton.action = #selector(changeFontFamily(_:))
        fontFamilyButton.setAccessibilityLabel(fontFamily)

        let fontSize = String(localized: "settings.fontSize")
        let fontSizes = EditorSettings.fontSizes
        fontSizeSlider.minValue = 0
        fontSizeSlider.maxValue = Double(fontSizes.count - 1)
        fontSizeSlider.numberOfTickMarks = fontSizes.count
        fontSizeSlider.allowsTickMarkValuesOnly = true
        fontSizeSlider.isContinuous = true
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(changeFontSize(_:))
        fontSizeSlider.setAccessibilityLabel(fontSize)
        fontSizeSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let lineSpacing = String(localized: "settings.lineSpacing")
        let lineSpacings = EditorSettings.LineSpacing.allCases
        lineSpacingControl.segmentCount = lineSpacings.count
        for (index, lineSpacing) in lineSpacings.enumerated() {
            lineSpacingControl.setLabel(lineSpacing.title, forSegment: index)
        }
        lineSpacingControl.trackingMode = .selectOne
        lineSpacingControl.controlSize = .small
        lineSpacingControl.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lineSpacingControl.target = self
        lineSpacingControl.action = #selector(changeLineSpacing(_:))
        lineSpacingControl.setAccessibilityLabel(lineSpacing)

        let grid = Self.columns([
            [Self.label(fontSize), fontSizeSlider],
            [Self.label(lineSpacing), lineSpacingControl],
            [Self.label(fontFamily), fontFamilyButton],
        ])
        // スライダーにはベースラインがないので、ラベルを縦の中心に揃える
        let sliderRow = grid.row(at: 0)
        sliderRow.rowAlignment = .none
        sliderRow.yPlacement = .center

        let optionsGrid = makeOptionsSection()
        let popUpGrid = Self.columns([makeLanguageRow(), makeIconRow()])
        let filesGrid = makeFilesSection()
        let startupGrid = makeStartupSection()
        updateSettingsControls()
        Self.alignLabelColumns([grid, optionsGrid, filesGrid, popUpGrid, startupGrid])
        return [grid, optionsGrid, filesGrid, Self.separator(), popUpGrid, startupGrid]
    }

    private func makeLanguageRow() -> [NSView] {
        let language = String(localized: "settings.language")
        languageButton.addItems(for: AppLanguage.self, title: \.title)
        languageButton.target = self
        languageButton.action = #selector(changeLanguage(_:))
        languageButton.setAccessibilityLabel(language)
        updateLanguage()
        return [Self.label(language), languageButton]
    }

    private func makeIconRow() -> [NSView] {
        let icon = String(localized: "settings.icon")
        iconPlacementButton.addItems(for: EditorSettings.IconPlacement.self, title: \.title)
        iconPlacementButton.selectItem(for: model.settings.iconPlacement)
        iconPlacementButton.target = self
        iconPlacementButton.action = #selector(changeIconPlacement(_:))
        iconPlacementButton.setAccessibilityLabel(icon)
        return [Self.label(icon), iconPlacementButton]
    }

    private func makeFilesSection() -> NSGridView {
        let fileAutosave = String(localized: "settings.fileAutosave")
        fileAutosaveButton.addItems(for: EditorSettings.FileAutosave.self, title: \.title)
        fileAutosaveButton.target = self
        fileAutosaveButton.action = #selector(changeFileAutosave(_:))
        fileAutosaveButton.setAccessibilityLabel(fileAutosave)
        let openBackups = Self.linkButton(
            String(localized: "settings.openBackups"),
            target: self,
            action: #selector(openBackups(_:))
        )

        let filesGrid = Self.columns([
            [Self.label(fileAutosave), fileAutosaveButton],
            [NSGridCell.emptyContentView, openBackups],
        ])
        filesGrid.rowSpacing = 6
        openBackupsRow = filesGrid.row(at: 1)
        return filesGrid
    }

    private func makeStartupSection() -> NSGridView {
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(changeLaunchAtLogin(_:))
        let requiresApproval = Self.note(String(localized: "settings.launchAtLogin.requiresApproval"))
        let openLoginItems = Self.linkButton(
            String(localized: "settings.openLoginItems"),
            target: self,
            action: #selector(openLoginItems(_:))
        )
        openLoginItems.setAccessibilityHelp(String(localized: "settings.openLoginItems.help"))

        let startupGrid = Self.columns([
            [Self.label(String(localized: "settings.startup")), launchAtLoginCheckbox],
            [NSGridCell.emptyContentView, requiresApproval],
            [NSGridCell.emptyContentView, openLoginItems],
        ])
        startupGrid.rowSpacing = 6
        requiresApprovalRow = startupGrid.row(at: 1)
        updateLaunchAtLogin()
        return startupGrid
    }

    private func updateLaunchAtLogin() {
        let status = LoginItem.status
        launchAtLoginCheckbox.state = status == .enabled || status == .requiresApproval ? .on : .off
        setRow(requiresApprovalRow, hidden: status != .requiresApproval)
    }

    private func updateSettingsControls() {
        let settings = model.settings
        fontFamilyButton.selectItem(for: settings.fontFamily)
        fontSizeSlider.integerValue = EditorSettings.fontSizes.firstIndex(of: settings.fontSize) ?? 0
        updateFontSizeValueDescription()
        lineSpacingControl.selectedSegment =
            EditorSettings.LineSpacing.allCases.firstIndex(of: settings.lineSpacing) ?? 0
        kerningCheckbox.state = settings.usesKerning ? .on : .off
        readableWidthCheckbox.state = settings.usesReadableWidth ? .on : .off
        readableWidthButton.selectItem(for: settings.readableWidth)
        newlinesCheckbox.state = settings.showsNewlines ? .on : .off
        whitespaceCheckbox.state = settings.showsWhitespace ? .on : .off
        whitespaceScopeButton.selectItem(for: settings.whitespaceScope)
        lineNumbersCheckbox.state = settings.showsLineNumbers ? .on : .off
        paragraphSpacingCheckbox.state = settings.addsParagraphSpacing ? .on : .off
        paragraphSpacingButton.selectItem(for: settings.paragraphSpacing)
        paragraphIndentCheckbox.state = settings.indentsParagraphs ? .on : .off
        paragraphIndentButton.selectItem(for: settings.paragraphIndent)
        fileAutosaveButton.selectItem(for: settings.fileAutosave)
        setRow(readableWidthRow, hidden: !settings.usesReadableWidth)
        setRow(whitespaceScopeRow, hidden: !settings.showsWhitespace)
        setRow(paragraphSpacingRow, hidden: !settings.addsParagraphSpacing)
        setRow(paragraphIndentRow, hidden: !settings.indentsParagraphs)
        setRow(openBackupsRow, hidden: settings.fileAutosave != .backup)
    }

    private func setRow(_ row: NSGridRow?, hidden: Bool) {
        guard let row, row.isHidden != hidden else { return }
        row.isHidden = hidden
        if isViewLoaded {
            updatePreferredContentSize()
        }
    }

    private func updateLanguage() {
        languageButton.selectItem(for: AppLanguage.current)
    }

    @objc private func settingsDidChange(_: Notification) {
        updateSettingsControls()
    }

    @objc private func windowDidBecomeKey(_: Notification) {
        updateLaunchAtLogin()
        updateLanguage()
    }

    /// スライダーの値は目盛りの位置なので、VoiceOverには実際の文字サイズを読ませる
    private func updateFontSizeValueDescription() {
        fontSizeSlider.setAccessibilityValueDescription(
            String(localized: "settings.fontSize.value \(Int(model.settings.fontSize))")
        )
    }

    @objc private func changeFontFamily(_ sender: NSPopUpButton) {
        guard let fontFamily = sender.selectedCase(of: EditorSettings.FontFamily.self) else { return }
        model.update { $0.fontFamily = fontFamily }
    }

    /// ドラッグしているあいだは同じ目盛りでも呼ばれ続けるので、値が変わったときだけ反映する
    @objc private func changeFontSize(_ sender: NSSlider) {
        let fontSize = EditorSettings.fontSizes[sender.integerValue]
        guard fontSize != model.settings.fontSize else { return }
        model.update { $0.fontSize = fontSize }
    }

    @objc private func changeLineSpacing(_ sender: NSSegmentedControl) {
        let lineSpacings = EditorSettings.LineSpacing.allCases
        guard lineSpacings.indices.contains(sender.selectedSegment) else { return }
        model.update { $0.lineSpacing = lineSpacings[sender.selectedSegment] }
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        guard let language = sender.selectedCase(of: AppLanguage.self), language != AppLanguage.current else { return }
        language.select()
        guard language.requiresRelaunch, let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "settings.language.relaunchRequired")
        alert.informativeText = String(localized: "settings.language.relaunchRequired.detail")
        alert.addButton(withTitle: String(localized: "settings.language.relaunchNow"))
        let later = alert.addButton(withTitle: String(localized: "settings.language.relaunchLater"))
        // NSAlertが⎋キーを割り当てるのは「キャンセル」などの決まった名前のボタンだけ
        later.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [relaunch] response in
            guard response == .alertFirstButtonReturn else { return }
            relaunch()
        }
    }

    @objc private func changeIconPlacement(_ sender: NSPopUpButton) {
        guard let placement = sender.selectedCase(of: EditorSettings.IconPlacement.self) else { return }
        model.update { $0.iconPlacement = placement }
    }

    @objc private func changeFileAutosave(_ sender: NSPopUpButton) {
        guard let fileAutosave = sender.selectedCase(of: EditorSettings.FileAutosave.self) else { return }
        model.update { $0.fileAutosave = fileAutosave }
    }

    /// バックアップはファイルに保存すると消えるので、まだ一度も書いていなければフォルダもない
    @objc private func openBackups(_: NSButton) {
        let directory = DraftLibrary.app.backupsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func changeLaunchAtLogin(_ sender: NSButton) {
        LoginItem.setEnabled(sender.state == .on)
        updateLaunchAtLogin()
    }

    @objc private func openLoginItems(_: NSButton) {
        LoginItem.openSystemSettings()
    }
}

extension GeneralSettingsPane {
    private func makeOptionsSection() -> NSGridView {
        kerningCheckbox.target = self
        kerningCheckbox.action = #selector(changeKerning(_:))

        readableWidthCheckbox.target = self
        readableWidthCheckbox.action = #selector(changeUsesReadableWidth(_:))
        readableWidthButton.addItems(for: EditorSettings.ReadableWidth.self, title: \.title)
        readableWidthButton.target = self
        readableWidthButton.action = #selector(changeReadableWidth(_:))
        readableWidthButton.setAccessibilityLabel(String(localized: "settings.readableWidth"))

        newlinesCheckbox.target = self
        newlinesCheckbox.action = #selector(changeShowsNewlines(_:))

        whitespaceCheckbox.target = self
        whitespaceCheckbox.action = #selector(changeShowsWhitespace(_:))
        whitespaceScopeButton.addItems(for: EditorSettings.WhitespaceScope.self, title: \.title)
        whitespaceScopeButton.target = self
        whitespaceScopeButton.action = #selector(changeWhitespaceScope(_:))
        whitespaceScopeButton.setAccessibilityLabel(String(localized: "settings.whitespaceScope"))

        lineNumbersCheckbox.target = self
        lineNumbersCheckbox.action = #selector(changeShowsLineNumbers(_:))

        paragraphSpacingCheckbox.target = self
        paragraphSpacingCheckbox.action = #selector(changeAddsParagraphSpacing(_:))
        paragraphSpacingButton.addItems(for: EditorSettings.ParagraphSpacing.self, title: \.title)
        paragraphSpacingButton.target = self
        paragraphSpacingButton.action = #selector(changeParagraphSpacing(_:))
        paragraphSpacingButton.setAccessibilityLabel(String(localized: "settings.paragraphSpacing"))

        paragraphIndentCheckbox.target = self
        paragraphIndentCheckbox.action = #selector(changeIndentsParagraphs(_:))
        paragraphIndentButton.addItems(for: EditorSettings.ParagraphIndent.self, title: \.title)
        paragraphIndentButton.target = self
        paragraphIndentButton.action = #selector(changeParagraphIndent(_:))
        paragraphIndentButton.setAccessibilityLabel(String(localized: "settings.paragraphIndent"))

        let optionsGrid = Self.columns([
            [Self.label(String(localized: "settings.editorOptions")), kerningCheckbox],
            [NSGridCell.emptyContentView, newlinesCheckbox],
            [NSGridCell.emptyContentView, whitespaceCheckbox],
            [NSGridCell.emptyContentView, whitespaceScopeButton],
            [NSGridCell.emptyContentView, lineNumbersCheckbox],
            [NSGridCell.emptyContentView, paragraphSpacingCheckbox],
            [NSGridCell.emptyContentView, paragraphSpacingButton],
            [NSGridCell.emptyContentView, paragraphIndentCheckbox],
            [NSGridCell.emptyContentView, paragraphIndentButton],
            [NSGridCell.emptyContentView, readableWidthCheckbox],
            [NSGridCell.emptyContentView, readableWidthButton],
        ])
        optionsGrid.rowSpacing = 6
        whitespaceScopeRow = indent(whitespaceScopeButton, under: whitespaceCheckbox, in: optionsGrid)
        paragraphSpacingRow = indent(paragraphSpacingButton, under: paragraphSpacingCheckbox, in: optionsGrid)
        paragraphIndentRow = indent(paragraphIndentButton, under: paragraphIndentCheckbox, in: optionsGrid)
        readableWidthRow = indent(readableWidthButton, under: readableWidthCheckbox, in: optionsGrid)
        return optionsGrid
    }

    private func indent(_ child: NSView, under parent: NSView, in grid: NSGridView) -> NSGridRow? {
        let cell = grid.cell(for: child)
        cell?.xPlacement = .none
        cell?.customPlacementConstraints = [
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 20),
        ]
        return cell?.row
    }

    @objc private func changeKerning(_ sender: NSButton) {
        model.update { $0.usesKerning = sender.state == .on }
    }

    @objc private func changeUsesReadableWidth(_ sender: NSButton) {
        model.update { $0.usesReadableWidth = sender.state == .on }
    }

    @objc private func changeReadableWidth(_ sender: NSPopUpButton) {
        guard let readableWidth = sender.selectedCase(of: EditorSettings.ReadableWidth.self) else { return }
        model.update { $0.readableWidth = readableWidth }
    }

    @objc private func changeShowsNewlines(_ sender: NSButton) {
        model.update { $0.showsNewlines = sender.state == .on }
    }

    @objc private func changeShowsWhitespace(_ sender: NSButton) {
        model.update { $0.showsWhitespace = sender.state == .on }
    }

    @objc private func changeShowsLineNumbers(_ sender: NSButton) {
        model.update { $0.showsLineNumbers = sender.state == .on }
    }

    @objc private func changeAddsParagraphSpacing(_ sender: NSButton) {
        model.update { $0.addsParagraphSpacing = sender.state == .on }
    }

    @objc private func changeParagraphSpacing(_ sender: NSPopUpButton) {
        guard let paragraphSpacing = sender.selectedCase(of: EditorSettings.ParagraphSpacing.self) else { return }
        model.update { $0.paragraphSpacing = paragraphSpacing }
    }

    @objc private func changeIndentsParagraphs(_ sender: NSButton) {
        model.update { $0.indentsParagraphs = sender.state == .on }
    }

    @objc private func changeParagraphIndent(_ sender: NSPopUpButton) {
        guard let paragraphIndent = sender.selectedCase(of: EditorSettings.ParagraphIndent.self) else { return }
        model.update { $0.paragraphIndent = paragraphIndent }
    }

    @objc private func changeWhitespaceScope(_ sender: NSPopUpButton) {
        guard let scope = sender.selectedCase(of: EditorSettings.WhitespaceScope.self) else { return }
        model.update { $0.whitespaceScope = scope }
    }
}

private extension NSPopUpButton {
    func addItems<Value: CaseIterable>(for _: Value.Type, title: (Value) -> String) {
        for value in Value.allCases {
            addItem(withTitle: title(value))
        }
    }

    func selectItem<Value: CaseIterable & Equatable>(for value: Value) {
        selectItem(at: Array(Value.allCases).firstIndex(of: value) ?? 0)
    }

    func selectedCase<Value: CaseIterable>(of _: Value.Type) -> Value? {
        let cases = Array(Value.allCases)
        return cases.indices.contains(indexOfSelectedItem) ? cases[indexOfSelectedItem] : nil
    }
}
