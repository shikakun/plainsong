import AppKit

final class ExtensionsSettingsPane: SettingsPane {
    private let model: SettingsModel
    private lazy var toolbarList = makeList(
        title: String(localized: "settings.toolbar"),
        items: \.toolbarItems
    ) { [weak self] kind in
        self?.showOptions(for: kind)
    }

    private lazy var statusBarList = makeList(
        title: String(localized: "settings.statusBar"),
        items: \.statusBarItems
    ) { [weak self] kind in
        self?.showOptions(for: kind)
    }

    init(model: SettingsModel) {
        self.model = model
        super.init(title: String(localized: "settings.extensions"))
    }

    override func makeSections() -> [NSView] {
        let showsSettingsButton = NSButton(
            checkboxWithTitle: String(localized: "settings.showsStatusBarSettingsButton"),
            target: self,
            action: #selector(changeShowsStatusBarSettingsButton(_:))
        )
        showsSettingsButton.state = model.settings.showsStatusBarSettingsButton ? .on : .off
        let showsOnHover = NSButton(
            checkboxWithTitle: String(localized: "settings.showsStatusBarOnHover"),
            target: self,
            action: #selector(changeShowsStatusBarOnHover(_:))
        )
        showsOnHover.state = model.settings.showsStatusBarOnHover ? .on : .off
        return [
            GroupSection(title: String(localized: "settings.toolbar"), content: toolbarList.view),
            GroupSection(
                title: String(localized: "settings.statusBar"),
                content: statusBarList.view,
                footer: [showsSettingsButton, showsOnHover]
            ),
        ]
    }

    /// 表の高さはウィンドウに置いて幅が決まるまでわからないので、決まったらペインの高さを合わせ直す
    override func viewDidLayout() {
        super.viewDidLayout()
        let fitted = [toolbarList, statusBarList].map { $0.fitHeight() }
        if fitted.contains(true) {
            updatePreferredContentSize()
        }
    }

    private func makeList<Kind: ExtensionItemKind>(
        title: String,
        items: WritableKeyPath<EditorSettings, [ExtensionItem<Kind>]>,
        showOptions: @escaping (Kind) -> Void = { _ in }
    ) -> ExtensionItemList {
        ExtensionItemList(
            title: title,
            rows: { [model] in model.settings[keyPath: items].map(ExtensionItemList.Row.init) },
            onMove: { [model] source, destination in
                model.update { settings in
                    let item = settings[keyPath: items].remove(at: source)
                    settings[keyPath: items].insert(item, at: destination)
                }
            },
            onToggle: { [model] row, isEnabled in
                model.update { $0[keyPath: items][row].isEnabled = isEnabled }
            },
            onShowOptions: { [model] row in
                showOptions(model.settings[keyPath: items][row].kind)
            }
        )
    }

    private func showOptions(for kind: ToolbarItemKind) {
        guard let window = view.window else { return }
        SettingsSheetController(title: kind.title, content: ToolbarItemOptionsView(kind: kind, model: model))
            .begin(for: window)
    }

    private func showOptions(for kind: StatusBarItemKind) {
        guard let window = view.window else { return }
        let content: NSView
        switch kind {
        case .characterCount: content = CharacterCountOptionsView(model: model)
        case .wordCount: content = WordCountOptionsView(model: model)
        case .fileEncoding, .lineEnding: return
        }
        SettingsSheetController(title: kind.title, content: content).begin(for: window)
    }

    @objc private func changeShowsStatusBarSettingsButton(_ sender: NSButton) {
        model.update { $0.showsStatusBarSettingsButton = sender.state == .on }
    }

    @objc private func changeShowsStatusBarOnHover(_ sender: NSButton) {
        model.update { $0.showsStatusBarOnHover = sender.state == .on }
    }
}

private final class ToolbarItemOptionsView: NSStackView {
    private let kind: ToolbarItemKind
    private let model: SettingsModel

    init(kind: ToolbarItemKind, model: SettingsModel) {
        self.kind = kind
        self.model = model
        super.init(frame: .zero)
        let checkbox = NSButton(
            checkboxWithTitle: kind.selectionOptionTitle ?? "",
            target: self,
            action: #selector(change(_:))
        )
        checkbox.state = model.settings.toolbarItemsIgnoringSelection.contains(kind) ? .off : .on
        addArrangedSubview(checkbox)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    @objc private func change(_ sender: NSButton) {
        model.update { settings in
            if sender.state == .on {
                settings.toolbarItemsIgnoringSelection.remove(kind)
            } else {
                settings.toolbarItemsIgnoringSelection.insert(kind)
            }
        }
    }
}

private final class CharacterCountOptionsView: NSStackView {
    private static let options: [(String.LocalizationValue, WritableKeyPath<CharacterCountOptions, Bool>)] = [
        ("settings.characterCount.includesSpaces", \.includesSpaces),
        ("settings.characterCount.includesIdeographicSpaces", \.includesIdeographicSpaces),
        ("settings.characterCount.includesTabs", \.includesTabs),
        ("settings.characterCount.includesNewlines", \.includesNewlines),
    ]

    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        let checkboxes = Self.options.enumerated().map { index, option in
            let checkbox = NSButton(
                checkboxWithTitle: String(localized: option.0),
                target: self,
                action: #selector(change(_:))
            )
            checkbox.tag = index
            checkbox.state = model.settings.characterCount[keyPath: option.1] ? .on : .off
            return checkbox
        }
        let width = checkboxes.map(\.intrinsicContentSize.width).max() ?? 0
        let note = wrappingNote(String(localized: "settings.characterCount.description"), width: width)
        setViews(checkboxes + [note], in: .top)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    @objc private func change(_ sender: NSButton) {
        let keyPath = Self.options[sender.tag].1
        model.update { $0.characterCount[keyPath: keyPath] = sender.state == .on }
    }
}

/// 行末に1文字だけ残らないよう、`lineBreakStrategy`を標準にする
private func wrappingNote(_ text: String, width: CGFloat) -> NSTextField {
    let note = SettingsPane.note(text)
    note.preferredMaxLayoutWidth = width
    note.lineBreakStrategy = .standard
    return note
}

private extension WordCountMethod {
    var optionTitle: String {
        switch self {
        case .allLanguages: String(localized: "settings.wordCount.allLanguages")
        case .japaneseAndChineseByCharacter: String(localized: "settings.wordCount.japaneseAndChineseByCharacter")
        case .englishOnly: String(localized: "settings.wordCount.englishOnly")
        }
    }

    var optionDescription: String {
        switch self {
        case .allLanguages: String(localized: "settings.wordCount.allLanguages.description")
        case .japaneseAndChineseByCharacter:
            String(localized: "settings.wordCount.japaneseAndChineseByCharacter.description")
        case .englishOnly: String(localized: "settings.wordCount.englishOnly.description")
        }
    }
}

private final class WordCountOptionsView: NSStackView {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        let radios = WordCountMethod.allCases.enumerated().map { index, method in
            // 同じ親ビューにあって同じアクションを持つラジオボタンは、AppKitが1つのグループとして扱う
            let radio = NSButton(radioButtonWithTitle: method.optionTitle, target: self, action: #selector(change(_:)))
            radio.tag = index
            radio.state = model.settings.wordCount == method ? .on : .off
            return radio
        }
        let width = radios.map(\.intrinsicContentSize.width).max() ?? 0
        for (radio, method) in zip(radios, WordCountMethod.allCases) {
            addArrangedSubview(radio)
            addArrangedSubview(Self.indentedNote(method.optionDescription, under: radio, width: width))
            setCustomSpacing(2, after: radio)
        }
    }

    private static func indentedNote(_ text: String, under radio: NSButton, width: CGFloat) -> NSView {
        let indent = radio.cell?.titleRect(forBounds: NSRect(origin: .zero, size: radio.intrinsicContentSize)).minX ?? 0
        let note = wrappingNote(text, width: width - indent)
        note.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(note)
        NSLayoutConstraint.activate([
            note.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent),
            note.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            note.topAnchor.constraint(equalTo: container.topAnchor),
            note.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    @objc private func change(_ sender: NSButton) {
        model.update { $0.wordCount = WordCountMethod.allCases[sender.tag] }
    }
}
