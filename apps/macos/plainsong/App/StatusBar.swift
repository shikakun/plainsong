import AppKit

final class StatusBar: NSView {
    static let height: CGFloat = 32
    private static let margin: CGFloat = 8
    /// 歯車のボタンの右端から、中のアイコンの右端までの幅
    private static let settingsIconPadding: CGFloat = 12

    private let textView: NSTextView
    private let background = BackgroundView()
    private let items = NSStackView()
    private lazy var itemsLeading = items.leadingAnchor.constraint(equalTo: leadingAnchor)
    private let settingsButton: NSButton
    private lazy var settingsTrailing = settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor)
    private var characterCount: CountField<CharacterCountOptions>?
    private var wordCount: CountField<WordCountMethod>?
    private var fileEncoding: StatusBarField?
    private var lineEnding: StatusBarField?
    private var showsOnHover = false
    private var isPointerInside = false
    private var isTextBehind = false

    var fileEncodingName = FileEncoding.utf8.name {
        didSet { fileEncoding?.stringValue = fileEncodingName }
    }

    var lineEndingName = LineEnding.lf.name {
        didSet { lineEnding?.stringValue = lineEndingName }
    }

    var backgroundColor: NSColor? {
        get { background.fillColor }
        set { background.fillColor = newValue }
    }

    var leadingInset: CGFloat {
        get { itemsLeading.constant }
        set { itemsLeading.constant = newValue }
    }

    var trailingInset: CGFloat {
        get { Self.settingsIconPadding - settingsTrailing.constant }
        set { settingsTrailing.constant = Self.settingsIconPadding - newValue }
    }

    private var isRevealed: Bool {
        !showsOnHover || isPointerInside
    }

    private var showsBackground: Bool {
        showsOnHover ? isPointerInside : isTextBehind
    }

    init(textView: NSTextView) {
        self.textView = textView
        settingsButton = NSButton(
            image: NSImage(systemSymbolName: "gear", accessibilityDescription: nil) ?? NSImage(),
            target: nil,
            action: #selector(AppDelegate.showSettings(_:))
        )
        super.init(frame: .zero)

        background.wantsLayer = true
        background.alphaValue = 0
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)

        items.orientation = .horizontal
        items.spacing = NSFont.systemFontSize
        items.translatesAutoresizingMaskIntoConstraints = false
        addSubview(items)

        let title = String(localized: "settings.title")
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.showsBorderOnlyWhileMouseInside = true
        settingsButton.controlSize = .regular
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.toolTip = title
        settingsButton.setAccessibilityLabel(title)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsButton)

        NSLayoutConstraint.activate([
            itemsLeading,
            items.centerYAnchor.constraint(equalTo: centerYAnchor),
            items.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -Self.margin),
            settingsTrailing,
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))

        // 本文のビューは、文字がステータスバーの帯まで届くと最小の高さを超えて伸びるので、高さの変化で気づける
        if let clipView = textView.enclosingScrollView?.contentView {
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(textDidMove(_:)),
                    name: name,
                    object: clipView
                )
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidMove(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    func update(with settings: EditorSettings) {
        settingsButton.isHidden = !settings.showsStatusBarSettingsButton
        showsOnHover = settings.showsStatusBarOnHover
        isTextBehind = measureTextBehind()
        background.alphaValue = showsBackground ? 1 : 0
        for view in [items, settingsButton] {
            view.alphaValue = isRevealed ? 1 : 0
        }
        let kinds = settings.enabledStatusBarItems
        characterCount = countField(
            characterCount,
            counter: settings.characterCount,
            isEnabled: kinds.contains(.characterCount)
        )
        wordCount = countField(wordCount, counter: settings.wordCount, isEnabled: kinds.contains(.wordCount))
        fileEncoding = valueField(fileEncoding, kind: .fileEncoding, value: fileEncodingName, in: kinds)
        lineEnding = valueField(lineEnding, kind: .lineEnding, value: lineEndingName, in: kinds)
        let views = kinds.compactMap(view(for:))
        // ウィンドウの大きさを保つ優先度より低くし、入りきらないときはウィンドウを広げずに省略する。後ろの項目ほど先に縮める
        for (index, view) in views.enumerated() {
            view.setContentCompressionResistancePriority(.defaultLow + Float(views.count - index), for: .horizontal)
        }
        items.setViews(views, in: .leading)
    }

    private func countField<Counter: StatusBarCounter>(
        _ field: CountField<Counter>?,
        counter: Counter,
        isEnabled: Bool
    ) -> CountField<Counter>? {
        guard isEnabled else { return nil }
        let field = field ?? CountField(textView: textView, counter: counter)
        field.counter = counter
        return field
    }

    private func valueField(
        _ field: StatusBarField?,
        kind: StatusBarItemKind,
        value: String,
        in kinds: [StatusBarItemKind]
    ) -> StatusBarField? {
        guard kinds.contains(kind) else { return nil }
        let field = field ?? StatusBarField()
        field.setAccessibilityLabel(kind.title)
        field.stringValue = value
        return field
    }

    private func view(for kind: StatusBarItemKind) -> NSView? {
        switch kind {
        case .characterCount: characterCount
        case .wordCount: wordCount
        case .fileEncoding: fileEncoding
        case .lineEnding: lineEnding
        }
    }

    override func mouseEntered(with _: NSEvent) {
        isPointerInside = true
        fade()
    }

    override func mouseExited(with _: NSEvent) {
        isPointerInside = false
        fade()
    }

    @objc private func textDidMove(_: Notification) {
        let isBehind = measureTextBehind()
        guard isBehind != isTextBehind else { return }
        isTextBehind = isBehind
        fade()
    }

    /// 本文のビューは、文字がステータスバーの帯に届くまでは最小の高さのままで、下端は帯より上にある。届くと文字に合わせて伸びる
    /// 文字を組んだ範囲（usageBoundsForTextContainer）は、文字を消してもすぐには縮まないので使わない
    private func measureTextBehind() -> Bool {
        convert(NSPoint(x: 0, y: textView.bounds.maxY), from: textView).y < Self.height
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isRevealed ? super.hitTest(point) : nil
    }

    /// 本文のスクロールビューの中に置いていないので、ステータスバーの上でのスクロールを本文に渡す
    override func scrollWheel(with event: NSEvent) {
        textView.enclosingScrollView?.scrollWheel(with: event)
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    private func fade() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            background.animator().alphaValue = showsBackground ? 1 : 0
            for view in [items, settingsButton] {
                view.animator().alphaValue = isRevealed ? 1 : 0
            }
        }
    }
}

/// CGColorは外観が変わっても追従しないので、塗り直すたびに色を取り直す
private final class BackgroundView: NSView {
    var fillColor: NSColor? {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = .separatorColor
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)
        NSLayoutConstraint.activate([
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = (fillColor ?? .textBackgroundColor).cgColor
    }
}

private protocol StatusBarCounter: Equatable {
    func count(in string: NSString, range: NSRange?) -> Int
    static func total(_ count: Int) -> String
    static func selected(_ count: Int) -> String
}

extension CharacterCountOptions: @MainActor StatusBarCounter {
    static func total(_ count: Int) -> String {
        String(localized: "statusBar.characterCount \(count)")
    }

    static func selected(_ count: Int) -> String {
        String(localized: "statusBar.characterCount.selected \(count)")
    }
}

extension WordCountMethod: @MainActor StatusBarCounter {
    static func total(_ count: Int) -> String {
        String(localized: "statusBar.wordCount \(count)")
    }

    static func selected(_ count: Int) -> String {
        String(localized: "statusBar.wordCount.selected \(count)")
    }
}

private class StatusBarField: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = true
        isBordered = false
        drawsBackground = false
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textColor = .secondaryLabelColor
        lineBreakMode = .byTruncatingTail
        allowsExpansionToolTips = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }
}

private final class CountField<Counter: StatusBarCounter>: StatusBarField {
    private weak var textView: NSTextView?
    private var isCountScheduled = false
    /// nilなら次に数えるときに全文を数える
    private var paragraphCounts: ParagraphCounts?

    var counter: Counter {
        didSet {
            if counter != oldValue {
                paragraphCounts = nil
                scheduleCount()
            }
        }
    }

    init(textView: NSTextView, counter: Counter) {
        self.textView = textView
        self.counter = counter
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textViewDidChangeSelection(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        scheduleCount()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    @objc private func textDidProcessEditing(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage,
              storage.editedMask.contains(.editedCharacters)
        else { return }
        let string = storage.mutableString
        paragraphCounts?.update(
            string: string,
            editedRange: storage.editedRange,
            changeInLength: storage.changeInLength
        ) { counter.count(in: string, range: $0) }
        scheduleCount()
    }

    @objc private func textViewDidChangeSelection(_: Notification) {
        scheduleCount()
    }

    /// 編集の途中では変換中の文字の状態が定まらないので、編集を終えてから数える。1回の操作で何度編集されたり選択が変わったりしても、数えるのは1回にする
    private func scheduleCount() {
        guard !isCountScheduled else { return }
        isCountScheduled = true
        Task {
            isCountScheduled = false
            count()
        }
    }

    /// 変換中の読みがなで数が増減しないよう、確定するまでは数え直さない
    private func count() {
        guard let textView, !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let string = storage.mutableString
        let paragraphCounts = paragraphCounts
            ?? ParagraphCounts(string: string) { counter.count(in: string, range: $0) }
        self.paragraphCounts = paragraphCounts
        let total = Counter.total(paragraphCounts.total)
        let selectedCount = textView.nonEmptySelectedRanges
            .reduce(0) { $0 + paragraphCounts.count(in: $1) { counter.count(in: string, range: $0) } }
        guard selectedCount > 0 else {
            stringValue = total
            return
        }
        let selected = Counter.selected(selectedCount)
        stringValue = String(localized: "statusBar.countWithSelection \(total) \(selected)")
    }
}
