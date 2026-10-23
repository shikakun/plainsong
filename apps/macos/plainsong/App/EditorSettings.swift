import AppKit

struct EditorSettings: Equatable {
    static let fontSizes: [CGFloat] = [12, 14, 16, 18, 21]
    static let tabEms: CGFloat = 2

    /// 下書きは、この設定に関係なく常に保存する
    nonisolated enum FileAutosave: String, CaseIterable {
        case off
        case backup
        case inPlace

        private static let key = "fileAutosave"

        /// NSDocumentが書類を開くたびに問い合わせるので、`EditorSettings`を介さずに読む
        static var current: Self {
            load(from: .standard)
        }

        var title: String {
            switch self {
            case .off: String(localized: "settings.fileAutosave.off")
            case .backup: String(localized: "settings.fileAutosave.backup")
            case .inPlace: String(localized: "settings.fileAutosave.inPlace")
            }
        }

        static func load(from defaults: UserDefaults) -> Self {
            defaults.string(forKey: key).flatMap(Self.init) ?? .backup
        }

        func save(to defaults: UserDefaults) {
            defaults.set(rawValue, forKey: Self.key)
        }
    }

    var fontFamily = FontFamily.sansSerif
    var fontSize: CGFloat = 16
    var lineSpacing = LineSpacing.standard
    var usesKerning = false
    var usesReadableWidth = false
    var readableWidth = ReadableWidth.standard
    var showsNewlines = false
    var showsWhitespace = false
    var whitespaceScope = WhitespaceScope.all
    var showsLineNumbers = false
    var addsParagraphSpacing = false
    var paragraphSpacing = ParagraphSpacing.halfLine
    var indentsParagraphs = false
    var paragraphIndent = ParagraphIndent.standard
    var theme = ThemeReference.standard
    var iconPlacement = IconPlacement.dock
    var fileAutosave = FileAutosave.backup
    var toolbarItems = ExtensionItem<ToolbarItemKind>.defaults
    /// 選択していても全文を対象にする項目。例外として持つので、あとから増えた項目は、はじめは選択したテキストを対象にする
    var toolbarItemsIgnoringSelection: Set<ToolbarItemKind> = []
    var showsStatusBarSettingsButton = true
    var showsStatusBarOnHover = false
    var statusBarItems = ExtensionItem<StatusBarItemKind>.defaults
    var characterCount = CharacterCountOptions()
    var wordCount = WordCountMethod.allLanguages

    var enabledToolbarItems: [ToolbarItemKind] {
        toolbarItems.filter(\.isEnabled).map(\.kind)
    }

    var enabledStatusBarItems: [StatusBarItemKind] {
        statusBarItems.filter(\.isEnabled).map(\.kind)
    }

    func paragraphStyle(lineHeight: CGFloat) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.lineSpacing = lineHeight * (lineSpacing.multiplier - 1)
        paragraphStyle.paragraphSpacing = addsParagraphSpacing ? lineHeight * paragraphSpacing.lines : 0
        paragraphStyle.firstLineHeadIndent = indentsParagraphs ? fontSize * paragraphIndent.ems : 0
        paragraphStyle.alignment = usesReadableWidth ? .justified : .natural
        // 標準のタブストップは28pt間隔で12個しかないので、空にして`defaultTabInterval`の間隔で並べる
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = fontSize * Self.tabEms
        return paragraphStyle
    }

    private static let fontFamilyKey = "fontFamily"
    private static let fontSizeKey = "fontSize"
    private static let lineSpacingKey = "lineSpacing"
    private static let usesKerningKey = "usesKerning"
    private static let usesReadableWidthKey = "usesReadableWidth"
    private static let readableWidthKey = "readableWidth"
    private static let showsNewlinesKey = "showsNewlines"
    private static let showsWhitespaceKey = "showsWhitespace"
    private static let whitespaceScopeKey = "whitespaceScope"
    private static let showsLineNumbersKey = "showsLineNumbers"
    private static let addsParagraphSpacingKey = "addsParagraphSpacing"
    private static let paragraphSpacingKey = "paragraphSpacing"
    private static let indentsParagraphsKey = "indentsParagraphs"
    private static let paragraphIndentKey = "paragraphIndent"
    private static let themeKey = "theme"
    private static let iconPlacementKey = "iconPlacement"
    private static let toolbarItemOrderKey = "toolbarItemOrder"
    private static let enabledToolbarItemsKey = "enabledToolbarItems"
    private static let toolbarItemsIgnoringSelectionKey = "toolbarItemsIgnoringSelection"
    private static let showsStatusBarSettingsButtonKey = "showsStatusBarSettingsButton"
    private static let showsStatusBarOnHoverKey = "showsStatusBarOnHover"
    private static let statusBarItemOrderKey = "statusBarItemOrder"
    private static let enabledStatusBarItemsKey = "enabledStatusBarItems"

    static func load() -> EditorSettings {
        let defaults = UserDefaults.standard
        var settings = EditorSettings()
        settings.fontFamily = defaults.value(forKey: fontFamilyKey, default: settings.fontFamily)
        let fontSize = CGFloat(defaults.double(forKey: fontSizeKey))
        if fontSizes.contains(fontSize) {
            settings.fontSize = fontSize
        }
        settings.lineSpacing = defaults.value(forKey: lineSpacingKey, default: settings.lineSpacing)
        if let usesKerning = defaults.object(forKey: usesKerningKey) as? Bool {
            settings.usesKerning = usesKerning
        }
        settings.usesReadableWidth = defaults.bool(forKey: usesReadableWidthKey)
        settings.readableWidth = defaults.value(forKey: readableWidthKey, default: settings.readableWidth)
        settings.showsNewlines = defaults.bool(forKey: showsNewlinesKey)
        settings.showsWhitespace = defaults.bool(forKey: showsWhitespaceKey)
        settings.whitespaceScope = defaults.value(forKey: whitespaceScopeKey, default: settings.whitespaceScope)
        settings.showsLineNumbers = defaults.bool(forKey: showsLineNumbersKey)
        settings.addsParagraphSpacing = defaults.bool(forKey: addsParagraphSpacingKey)
        settings.paragraphSpacing = defaults.value(forKey: paragraphSpacingKey, default: settings.paragraphSpacing)
        settings.indentsParagraphs = defaults.bool(forKey: indentsParagraphsKey)
        settings.paragraphIndent = defaults.value(forKey: paragraphIndentKey, default: settings.paragraphIndent)
        if let theme = defaults.string(forKey: themeKey) {
            settings.theme = ThemeReference(rawValue: theme)
        }
        settings.iconPlacement = defaults.value(forKey: iconPlacementKey, default: settings.iconPlacement)
        settings.fileAutosave = .load(from: defaults)
        if let shows = defaults.object(forKey: showsStatusBarSettingsButtonKey) as? Bool {
            settings.showsStatusBarSettingsButton = shows
        }
        settings.showsStatusBarOnHover = defaults.bool(forKey: showsStatusBarOnHoverKey)
        settings.toolbarItems = ExtensionItem.load(
            from: defaults,
            orderKey: toolbarItemOrderKey,
            enabledKey: enabledToolbarItemsKey
        )
        settings.toolbarItemsIgnoringSelection = Set(
            (defaults.stringArray(forKey: toolbarItemsIgnoringSelectionKey) ?? []).compactMap(ToolbarItemKind.init)
        )
        settings.statusBarItems = ExtensionItem.load(
            from: defaults,
            orderKey: statusBarItemOrderKey,
            enabledKey: enabledStatusBarItemsKey
        )
        settings.characterCount = .load(from: defaults)
        settings.wordCount = .load(from: defaults)
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(fontFamily.rawValue, forKey: Self.fontFamilyKey)
        defaults.set(Double(fontSize), forKey: Self.fontSizeKey)
        defaults.set(lineSpacing.rawValue, forKey: Self.lineSpacingKey)
        defaults.set(usesKerning, forKey: Self.usesKerningKey)
        defaults.set(usesReadableWidth, forKey: Self.usesReadableWidthKey)
        defaults.set(readableWidth.rawValue, forKey: Self.readableWidthKey)
        defaults.set(showsNewlines, forKey: Self.showsNewlinesKey)
        defaults.set(showsWhitespace, forKey: Self.showsWhitespaceKey)
        defaults.set(whitespaceScope.rawValue, forKey: Self.whitespaceScopeKey)
        defaults.set(showsLineNumbers, forKey: Self.showsLineNumbersKey)
        defaults.set(addsParagraphSpacing, forKey: Self.addsParagraphSpacingKey)
        defaults.set(paragraphSpacing.rawValue, forKey: Self.paragraphSpacingKey)
        defaults.set(indentsParagraphs, forKey: Self.indentsParagraphsKey)
        defaults.set(paragraphIndent.rawValue, forKey: Self.paragraphIndentKey)
        defaults.set(theme.rawValue, forKey: Self.themeKey)
        defaults.set(iconPlacement.rawValue, forKey: Self.iconPlacementKey)
        fileAutosave.save(to: defaults)
        defaults.set(toolbarItems.map(\.kind.rawValue), forKey: Self.toolbarItemOrderKey)
        defaults.set(enabledToolbarItems.map(\.rawValue), forKey: Self.enabledToolbarItemsKey)
        defaults.set(
            ToolbarItemKind.allCases.filter(toolbarItemsIgnoringSelection.contains).map(\.rawValue),
            forKey: Self.toolbarItemsIgnoringSelectionKey
        )
        defaults.set(showsStatusBarSettingsButton, forKey: Self.showsStatusBarSettingsButtonKey)
        defaults.set(showsStatusBarOnHover, forKey: Self.showsStatusBarOnHoverKey)
        defaults.set(statusBarItems.map(\.kind.rawValue), forKey: Self.statusBarItemOrderKey)
        defaults.set(enabledStatusBarItems.map(\.rawValue), forKey: Self.enabledStatusBarItemsKey)
        characterCount.save(to: defaults)
        wordCount.save(to: defaults)
    }
}

extension EditorSettings {
    enum FontFamily: String, CaseIterable {
        case sansSerif
        case serif

        var title: String {
            switch self {
            case .sansSerif: String(localized: "settings.fontFamily.sansSerif")
            case .serif: String(localized: "settings.fontFamily.serif")
            }
        }

        func font(ofSize size: CGFloat) -> NSFont {
            let font = NSFont.systemFont(ofSize: size)
            switch self {
            case .sansSerif:
                // 日本語のフォールバック先としてOSが選ぶフォントは、全角を文字サイズの約0.92倍に縮めて描くので、明朝と大きさが揃わない
                let descriptor = font.fontDescriptor.addingAttributes([
                    .cascadeList: [NSFontDescriptor(name: "HiraginoSans-W4", size: size)],
                ])
                return NSFont(descriptor: descriptor, size: size) ?? font
            case .serif:
                return font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? font
            }
        }
    }

    enum LineSpacing: String, CaseIterable {
        case compact
        case standard
        case relaxed

        /// 行間を含まない1行の高さに対する、行送りの倍率
        var multiplier: CGFloat {
            switch self {
            case .compact: 1
            case .standard: 1.5
            case .relaxed: 2
            }
        }

        var title: String {
            switch self {
            case .compact: String(localized: "settings.lineSpacing.compact")
            case .standard: String(localized: "settings.lineSpacing.standard")
            case .relaxed: String(localized: "settings.lineSpacing.relaxed")
            }
        }
    }

    enum ReadableWidth: String, CaseIterable {
        case standard
        case english
        case japanese

        var ems: CGFloat {
            switch self {
            case .standard: Bundle.main.preferredLocalizations.first == "ja" ? Self.japanese.ems : Self.english.ems
            case .english: 29
            case .japanese: 40
            }
        }

        var title: String {
            switch self {
            case .standard: String(localized: "settings.readableWidth.standard")
            case .english: String(localized: "settings.readableWidth.english")
            case .japanese: String(localized: "settings.readableWidth.japanese")
            }
        }
    }

    enum ParagraphSpacing: String, CaseIterable {
        case halfLine
        case oneLine
        case twoLines

        var lines: CGFloat {
            switch self {
            case .halfLine: 0.5
            case .oneLine: 1
            case .twoLines: 2
            }
        }

        var title: String {
            switch self {
            case .halfLine: String(localized: "settings.paragraphSpacing.halfLine")
            case .oneLine: String(localized: "settings.paragraphSpacing.oneLine")
            case .twoLines: String(localized: "settings.paragraphSpacing.twoLines")
            }
        }
    }

    enum ParagraphIndent: String, CaseIterable {
        case standard
        case fullWidth
        case tab

        var ems: CGFloat {
            switch self {
            case .standard: Bundle.main.preferredLocalizations.first == "ja" ? Self.fullWidth.ems : Self.tab.ems
            case .fullWidth: 1
            case .tab: EditorSettings.tabEms
            }
        }

        var title: String {
            switch self {
            case .standard: String(localized: "settings.paragraphIndent.standard")
            case .fullWidth: String(localized: "settings.paragraphIndent.fullWidth")
            case .tab: String(localized: "settings.paragraphIndent.tab")
            }
        }
    }

    enum WhitespaceScope: String, CaseIterable {
        case all
        case selection
        case trailing

        var title: String {
            switch self {
            case .all: String(localized: "settings.whitespaceScope.all")
            case .selection: String(localized: "settings.whitespaceScope.selection")
            case .trailing: String(localized: "settings.whitespaceScope.trailing")
            }
        }
    }

    enum IconPlacement: String, CaseIterable {
        case dock
        case menuBar
        case both

        var showsInDock: Bool {
            self != .menuBar
        }

        var showsInMenuBar: Bool {
            self != .dock
        }

        var title: String {
            switch self {
            case .dock: String(localized: "settings.iconPlacement.dock")
            case .menuBar: String(localized: "settings.iconPlacement.menuBar")
            case .both: String(localized: "settings.iconPlacement.both")
            }
        }
    }
}

extension EditorSettings {
    /// 本文の左右の余白の最小値。行番号を出すときは、左だけこの2倍にして番号を置く
    var minimumInset: CGFloat {
        fontSize * 2
    }

    var lineNumberWidth: CGFloat {
        minimumInset * 2
    }

    /// 読みやすい幅で折り返すときは、左右を揃えて本文を中央に置く。揃えると行番号が入らないときは、左を行番号の幅にする
    func horizontalInsets(clipWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let minimumLeading = showsLineNumbers ? lineNumberWidth : minimumInset
        guard usesReadableWidth else { return (minimumLeading, minimumInset) }
        let maximumWidth = fontSize * readableWidth.ems
        let centeringInset = ((clipWidth - maximumWidth) / 2).rounded(.down)
        if centeringInset >= minimumLeading {
            return (centeringInset, centeringInset)
        }
        return (minimumLeading, max(minimumInset, (clipWidth - maximumWidth - minimumLeading).rounded(.down)))
    }
}

extension UserDefaults {
    func value<Value: RawRepresentable<String>>(forKey key: String, default defaultValue: Value) -> Value {
        string(forKey: key).flatMap(Value.init) ?? defaultValue
    }
}

/// 並び順とON/OFFはrawValueで保存するので、caseの名前を変えると設定が失われる
protocol ExtensionItemKind: RawRepresentable<String>, CaseIterable, Hashable where AllCases == [Self] {
    var title: String { get }
    var summary: String { get }
    var symbol: String? { get }
    var hasOptions: Bool { get }
}

extension ExtensionItemKind {
    var symbol: String? {
        nil
    }

    var hasOptions: Bool {
        false
    }
}

struct ExtensionItem<Kind: ExtensionItemKind>: Equatable {
    let kind: Kind
    var isEnabled: Bool

    static var defaults: [Self] {
        Kind.allCases.map { Self(kind: $0, isEnabled: false) }
    }

    static func load(from defaults: UserDefaults, orderKey: String, enabledKey: String) -> [Self] {
        func kinds(forKey key: String) -> [Kind] {
            (defaults.stringArray(forKey: key) ?? []).compactMap { Kind(rawValue: $0) }
        }
        let saved = kinds(forKey: orderKey)
        let order = saved + Kind.allCases.filter { !saved.contains($0) }
        let enabled = Set(kinds(forKey: enabledKey))
        return order.map { Self(kind: $0, isEnabled: enabled.contains($0)) }
    }
}

enum ToolbarItemKind: String, ExtensionItemKind {
    case copy
    case save
    case share
    case delete

    var title: String {
        switch self {
        case .copy: String(localized: "toolbarItem.copy")
        case .save: String(localized: "toolbarItem.save")
        case .share: String(localized: "toolbarItem.share")
        case .delete: String(localized: "toolbarItem.delete")
        }
    }

    var summary: String {
        switch self {
        case .copy: String(localized: "toolbarItem.copy.summary")
        case .save: String(localized: "toolbarItem.save.summary")
        case .share: String(localized: "toolbarItem.share.summary")
        case .delete: String(localized: "toolbarItem.delete.summary")
        }
    }

    var symbol: String? {
        switch self {
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .share: "square.and.arrow.up"
        case .delete: "trash"
        }
    }

    var selectionOptionTitle: String? {
        switch self {
        case .copy: String(localized: "settings.toolbarItem.copy.usesSelection")
        case .save: nil
        case .share: String(localized: "settings.toolbarItem.share.usesSelection")
        case .delete: String(localized: "settings.toolbarItem.delete.usesSelection")
        }
    }

    var hasOptions: Bool {
        selectionOptionTitle != nil
    }
}

enum StatusBarItemKind: String, ExtensionItemKind {
    case characterCount
    case wordCount
    case fileEncoding
    case lineEnding

    var title: String {
        switch self {
        case .characterCount: String(localized: "statusBarItem.characterCount")
        case .wordCount: String(localized: "statusBarItem.wordCount")
        case .fileEncoding: String(localized: "statusBarItem.fileEncoding")
        case .lineEnding: String(localized: "statusBarItem.lineEnding")
        }
    }

    var summary: String {
        switch self {
        case .characterCount: String(localized: "statusBarItem.characterCount.summary")
        case .wordCount: String(localized: "statusBarItem.wordCount.summary")
        case .fileEncoding: String(localized: "statusBarItem.fileEncoding.summary")
        case .lineEnding: String(localized: "statusBarItem.lineEnding.summary")
        }
    }

    var hasOptions: Bool {
        switch self {
        case .characterCount, .wordCount: true
        case .fileEncoding, .lineEnding: false
        }
    }
}
