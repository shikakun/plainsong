import AppKit

struct EditorSettings: Equatable {
    static let fontSizes: [CGFloat] = [12, 14, 16, 18, 21]
    nonisolated static let tabEms: CGFloat = 2

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
    var orientation = Orientation.horizontal
    var guide = Guide.blank
    var usesKerning = false
    var usesReadableWidth = false
    var readableWidth = ReadableWidth.standard
    var highlightsMarkdown = true
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
    var toolbarFindOpensReplace = false
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

    /// 原稿用紙で字送りを揃えるために和文のフォントへ差し替えると、その文字を含む行だけ高さの基準が変わり、マスからずれるので、本文全体を和文のフォントにする
    var bodyFont: NSFont {
        let font = fontFamily.font(ofSize: fontSize)
        return showsManuscriptGuide ? EditorSettings.japaneseFont(for: font) : font
    }

    static func japaneseFont(for font: NSFont) -> NSFont {
        CTFontCreateForString(font, "あ" as CFString, CFRange(location: 0, length: 1)) as NSFont
    }

    var manuscriptPaper: ManuscriptPaper {
        ManuscriptPaper(indent: indentsParagraphs ? Int(paragraphIndent.ems) : 0)
    }

    func paragraphStyle(lineHeight: CGFloat) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.lineSpacing = lineHeight * (lineSpacing.multiplier - 1)
        paragraphStyle.paragraphSpacing = usesParagraphSpacing ? lineHeight * paragraphSpacing.lines : 0
        // 原稿用紙の禁則は`ManuscriptPaper`が決めるので、TextKitの禁則や単語の折り返しを止める
        paragraphStyle.lineBreakMode = showsManuscriptGuide ? .byCharWrapping : .byWordWrapping
        paragraphStyle.firstLineHeadIndent = indentsParagraphs ? fontSize * paragraphIndent.ems : 0
        // 標準のタブストップは28pt間隔で12個しかないので、空にして`defaultTabInterval`の間隔で並べる
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = fontSize * Self.tabEms
        return paragraphStyle
    }

    private static let fontFamilyKey = "fontFamily"
    private static let fontSizeKey = "fontSize"
    private static let lineSpacingKey = "lineSpacing"
    private static let orientationKey = "orientation"
    private static let guideKey = "guide"
    private static let usesKerningKey = "usesKerning"
    private static let usesReadableWidthKey = "usesReadableWidth"
    private static let readableWidthKey = "readableWidth"
    private static let highlightsMarkdownKey = "highlightsMarkdown"
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
    private static let toolbarFindOpensReplaceKey = "toolbarFindOpensReplace"
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
        settings.orientation = defaults.value(forKey: orientationKey, default: settings.orientation)
        settings.guide = defaults.value(forKey: guideKey, default: settings.guide)
        if let usesKerning = defaults.object(forKey: usesKerningKey) as? Bool {
            settings.usesKerning = usesKerning
        }
        settings.usesReadableWidth = defaults.bool(forKey: usesReadableWidthKey)
        settings.readableWidth = defaults.value(forKey: readableWidthKey, default: settings.readableWidth)
        if let highlightsMarkdown = defaults.object(forKey: highlightsMarkdownKey) as? Bool {
            settings.highlightsMarkdown = highlightsMarkdown
        }
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
        settings.toolbarFindOpensReplace = defaults.bool(forKey: toolbarFindOpensReplaceKey)
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
        defaults.set(orientation.rawValue, forKey: Self.orientationKey)
        defaults.set(guide.rawValue, forKey: Self.guideKey)
        defaults.set(usesKerning, forKey: Self.usesKerningKey)
        defaults.set(usesReadableWidth, forKey: Self.usesReadableWidthKey)
        defaults.set(readableWidth.rawValue, forKey: Self.readableWidthKey)
        defaults.set(highlightsMarkdown, forKey: Self.highlightsMarkdownKey)
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
        defaults.set(toolbarFindOpensReplace, forKey: Self.toolbarFindOpensReplaceKey)
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
                // 日本語のフォールバック先としてOSが選ぶフォントは、全角を文字サイズの約0.92倍に縮めて描くので、明朝体と大きさが揃わない
                return Self.font(font.fontDescriptor, size: size, japanese: "HiraginoSans-W4") ?? font
            case .serif:
                // 和文のフォールバック先はOSの言語設定で変わり、日本語以外では縦中横に必要なhwidを持たない宋体になる
                let descriptor = font.fontDescriptor.withDesign(.serif) ?? font.fontDescriptor
                return Self.font(descriptor, size: size, japanese: "HiraMinProN-W3") ?? font
            }
        }

        static func monospacedFont(ofSize size: CGFloat) -> NSFont {
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            return Self.font(font.fontDescriptor, size: size, japanese: "HiraginoSans-W4") ?? font
        }

        /// OSに任せると和文が太字にならないことがあるので、ヒラギノの太いウェイトを指定する。明朝体にはW7がないのでW6にする
        func boldFont(ofSize size: CGFloat) -> NSFont {
            let font = NSFont.systemFont(ofSize: size, weight: .bold)
            let (descriptor, japanese) = switch self {
            case .sansSerif: (font.fontDescriptor, "HiraginoSans-W7")
            case .serif: (font.fontDescriptor.withDesign(.serif) ?? font.fontDescriptor, "HiraMinProN-W6")
            }
            return Self.font(descriptor, size: size, japanese: japanese) ?? font
        }

        private static func font(_ descriptor: NSFontDescriptor, size: CGFloat, japanese name: String) -> NSFont? {
            let cascaded = descriptor.addingAttributes([
                .cascadeList: [NSFontDescriptor(name: name, size: size)],
            ])
            return NSFont(descriptor: cascaded, size: size)
        }
    }

    enum Orientation: String, CaseIterable {
        case horizontal
        case vertical

        var layoutOrientation: NSLayoutManager.TextLayoutOrientation {
            switch self {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }
        }

        var title: String {
            switch self {
            case .horizontal: String(localized: "settings.orientation.horizontal")
            case .vertical: String(localized: "settings.orientation.vertical")
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
        case japaneseShort

        func ems(in orientation: Orientation) -> CGFloat {
            switch self {
            case .standard:
                if orientation == .vertical {
                    Self.japaneseShort.ems(in: orientation)
                } else if Bundle.main.preferredLocalizations.first == "ja" {
                    Self.japanese.ems(in: orientation)
                } else {
                    Self.english.ems(in: orientation)
                }
            case .english: 29
            case .japanese: 40
            case .japaneseShort: 20
            }
        }

        var title: String {
            switch self {
            case .standard: String(localized: "settings.readableWidth.standard")
            case .english: String(localized: "settings.readableWidth.english")
            case .japanese: String(localized: "settings.readableWidth.japanese")
            case .japaneseShort: String(localized: "settings.readableWidth.japaneseShort")
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

    var lineNumberGutter: CGFloat {
        minimumInset * 2
    }

    func lineInsets(
        clipLength: CGFloat,
        minimumLeading: CGFloat,
        minimumTrailing: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat) {
        if showsManuscriptGuide, !usesReadableWidth {
            let cells = manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            )
            return (minimumLeading, clipLength - minimumLeading - fontSize * CGFloat(cells))
        }
        guard usesReadableWidth else { return (minimumLeading, minimumTrailing) }
        let maximumLength = showsManuscriptGuide
            ? fontSize * CGFloat(manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            ))
            : fontSize * readableWidth.ems(in: orientation)
        let centeringInset = ((clipLength - maximumLength) / 2).rounded(.down)
        if centeringInset >= max(minimumLeading, minimumTrailing) {
            return (centeringInset, centeringInset)
        }
        return (minimumLeading, max(minimumTrailing, (clipLength - maximumLength - minimumLeading).rounded(.down)))
    }

    func manuscriptCells(clipLength: CGFloat, minimumLeading: CGFloat, minimumTrailing: CGFloat) -> Int {
        let fitting = max(Int((clipLength - minimumLeading - minimumTrailing) / fontSize), 1)
        return usesReadableWidth ? min(Int(readableWidth.ems(in: orientation)), fitting) : fitting
    }

    /// 原稿用紙のマス数がウィンドウで決まるあいだ、行末の余白はマスに満たない端数で増減する。広げると、幅を変えるたびに本文とマス目が揺れる
    func crossInsetExpansion(clipLength: CGFloat, minimumLeading: CGFloat, minimumTrailing: CGFloat) -> CGFloat {
        if showsManuscriptGuide {
            let cells = manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            )
            guard usesReadableWidth, cells >= Int(readableWidth.ems(in: orientation)) else { return 0 }
        }
        let trailing = lineInsets(
            clipLength: clipLength,
            minimumLeading: minimumLeading,
            minimumTrailing: minimumTrailing
        ).trailing
        return min((trailing - minimumTrailing) / 2, fontSize * 4).rounded(.down)
    }
}

nonisolated extension UserDefaults {
    func value<Value: RawRepresentable<String>>(forKey key: String, default defaultValue: Value) -> Value {
        string(forKey: key).flatMap(Value.init) ?? defaultValue
    }
}
