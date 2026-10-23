import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let editorWindow: NSWindow
    /// ステータスバーを本文に重ねるための入れ物。NSScrollViewは、サブビューにAuto Layoutの結果を反映しない
    private let container = NSView()
    private let scrollView = NSScrollView()
    private let textView: NSTextView
    private let layoutManager: LineHeightSegmentLayoutManager
    /// レイアウトマネージャーはデリゲートを弱参照で持つので、ここで持っておく
    private let whitespaceMarkers = WhitespaceMarkers()
    private var selectionObservation: (any NSObjectProtocol)?
    private var clipViewFrameObservation: (any NSObjectProtocol)?
    /// ツールバーを含む高さ。全画面でタイトルバーが隠れても余白が変わらないよう、全画面のあいだは測り直さない
    private var titlebarHeight: CGFloat = 0
    private var titlebarObservation: NSKeyValueObservation?
    private var settings: EditorSettings?
    private var toolbar: EditorToolbar?
    private var statusBar: StatusBar?
    private var lineNumberView: LineNumberView?
    private var theme: Theme?
    /// 「デフォルト」とテーマにないキーは、NSTextViewが最初に持っている選択範囲の色に戻す
    private let standardSelectedTextAttributes: [NSAttributedString.Key: Any]
    var fileEncoding = FileEncoding.utf8 {
        didSet { statusBar?.fileEncodingName = fileEncoding.name }
    }

    var lineEnding = LineEnding.lf {
        didSet { statusBar?.lineEndingName = lineEnding.name }
    }

    private var needsMixedLineEndingNotice = false

    var textStorage: NSTextStorage? {
        textView.textStorage
    }

    init(text: String, settings: EditorSettings) {
        editorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        (textView, layoutManager) = Self.makeTextView()
        standardSelectedTextAttributes = textView.selectedTextAttributes
        super.init(window: editorWindow)
        editorWindow.delegate = self
        editorWindow.titleVisibility = .hidden
        editorWindow.titlebarAppearsTransparent = true
        editorWindow.titlebarSeparatorStyle = .none
        editorWindow.isReleasedWhenClosed = false
        place()

        layoutManager.delegate = whitespaceMarkers
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
        // 上下の余白はウィンドウの端から測る。スクロールビューはタイトルバーの分を、クリップビューは上下6ptを自動で足すので、両方とも切る
        // クリップビューの自動調整を切ると、スクロールビューのcontentInsetsは反映されないので、クリップビューに直接指定する
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        Self.configure(textView)
        textView.delegate = self
        // NSTextViewが背景を塗ると、入力のたびに文書の高さ全体ぶんの描画バッファを確保してしまう
        textView.drawsBackground = false
        scrollView.backgroundColor = .textBackgroundColor
        apply(settings)
        // 代入するとカーソルは末尾に移る
        textView.string = text
        editorWindow.contentView = container
        editorWindow.makeFirstResponder(textView)
        textView.scrollRangeToVisible(textView.selectedRange())
        // 全画面のあいだにツールバーを出し入れしたときは、全画面から戻ったときに測り直す
        // ウィンドウの大きさが変わるのはメインスレッドだけなので、通知もメインスレッドで届く
        titlebarObservation = editorWindow.observe(\.contentLayoutRect) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.titlebarDidChange() }
        }
        // ウィンドウを書類に加えるまで、どの取り消しの履歴を使うかが決まらないので、すべての履歴の通知を受けて見分ける
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(undoManagerDidChange(_:)),
                name: name,
                object: nil
            )
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    /// 下書きのタイトルは見せないが、VoiceOverやウインドウメニューで読まれる。ファイルは、ファイル名とプロキシアイコンを見せる
    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        editorWindow.titleVisibility = (document as? NSDocument)?.fileURL == nil ? .hidden : .visible
    }

    /// 書類の取り消しの履歴を使い、NSDocumentに変更を知らせる
    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    func window(_: NSWindow, willEncodeRestorableState state: NSCoder) {
        if let id = (document as? TextDocument)?.draftID {
            state.encode(id as NSString, forKey: TextDocument.draftIDKey)
        }
    }

    /// 取り消しの履歴には入れない
    func replaceText(_ text: String) {
        textView.discardMarkedTextIfNeeded()
        textView.string = text
    }

    func breakUndoCoalescing() {
        textView.breakUndoCoalescing()
    }

    func apply(_ settings: EditorSettings) {
        guard settings != self.settings else { return }
        let previous = self.settings
        self.settings = settings
        let typesettingChanged = settings.fontFamily != previous?.fontFamily
            || settings.fontSize != previous?.fontSize
            || settings.lineSpacing != previous?.lineSpacing
            || settings.usesKerning != previous?.usesKerning
            || settings.addsParagraphSpacing != previous?.addsParagraphSpacing
            || settings.paragraphSpacing != previous?.paragraphSpacing
            || settings.indentsParagraphs != previous?.indentsParagraphs
            || settings.paragraphIndent != previous?.paragraphIndent
            || settings.usesReadableWidth != previous?.usesReadableWidth
        if typesettingChanged {
            applyFont(of: settings)
        }
        // 起動して「デフォルト」のままなら、システムの色のままなので何もしない
        if settings.theme != previous?.theme ?? .standard {
            applyTheme(ThemeLibrary().theme(for: settings.theme))
        }
        applyWhitespace(of: settings)
        applyLineNumbers(of: settings)
        observeClipViewFrame(settings.usesReadableWidth || settings.showsLineNumbers)
        applyToolbar(of: settings)
        applyStatusBar(of: settings)
        updateInsets()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// 本文全体を1回の編集で書き換える。属性の変更なので、TextStoreは記録せず、取り消しの履歴にも入らない
    private func applyFont(of settings: EditorSettings) {
        let font = settings.fontFamily.font(ofSize: settings.fontSize)
        // 明朝の欧文は文字サイズによって行の高さが1ptずれるので、フォントを切り替えても行送りが変わらないようゴシックの高さに揃える
        let sansSerif = EditorSettings.FontFamily.sansSerif.font(ofSize: settings.fontSize)
        let lineHeight = Self.metrics.defaultLineHeight(for: sansSerif)
        let paragraphStyle = settings.paragraphStyle(lineHeight: lineHeight)
        layoutManager.lineHeight = lineHeight

        // defaultParagraphStyleは、変換を通さずに入力した文字には付かないので、入力する文字の属性に指定する
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        // 0を指定すると、欧文のカーニングに加えて、和文の約物の詰めと和欧間の空きも止まる
        let kern: NSNumber? = settings.usesKerning ? nil : 0
        textView.typingAttributes[.kern] = kern
        if let storage = textView.textStorage, storage.length > 0 {
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes([.font: font, .paragraphStyle: paragraphStyle], range: range)
            if let kern {
                storage.addAttribute(.kern, value: kern, range: range)
            } else {
                storage.removeAttribute(.kern, range: range)
            }
            storage.endEditing()
        }
    }

    /// 文字の色は、本文全体と入力する文字の属性を書き換える。TextStoreは記録せず、取り消しの履歴にも入らない
    private func applyTheme(_ theme: Theme?) {
        self.theme = theme
        editorWindow.appearance = theme?.appearance
        scrollView.backgroundColor = theme?.background ?? .textBackgroundColor
        textView.textColor = theme?.foreground ?? .textColor
        textView.insertionPointColor = theme?.cursor ?? .textInsertionPointColor
        var selectedTextAttributes = standardSelectedTextAttributes
        selectedTextAttributes[.backgroundColor] = theme?.selectionBackground
            ?? standardSelectedTextAttributes[.backgroundColor]
        selectedTextAttributes[.foregroundColor] = theme?.selectionForeground
            ?? standardSelectedTextAttributes[.foregroundColor]
        textView.selectedTextAttributes = selectedTextAttributes
        statusBar?.backgroundColor = theme?.background
        whitespaceMarkers.color = theme?.foreground.map { $0.withAlphaComponent(0.3) } ?? .tertiaryLabelColor
        if whitespaceMarkers.scope != nil || whitespaceMarkers.showsNewlines {
            redrawWhitespace()
        }
    }

    private func applyWhitespace(of settings: EditorSettings) {
        let scope = settings.showsWhitespace ? settings.whitespaceScope : nil
        guard scope != whitespaceMarkers.scope || settings.showsNewlines != whitespaceMarkers.showsNewlines
        else { return }
        whitespaceMarkers.scope = scope
        whitespaceMarkers.showsNewlines = settings.showsNewlines
        if case .selection = scope {
            whitespaceMarkers.selectedRanges = textView.nonEmptySelectedRanges
            // 選択範囲が変わるのはメインスレッドだけなので、通知もメインスレッドで届く
            selectionObservation = selectionObservation ?? NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.selectionDidChange() }
            }
        } else if let selectionObservation {
            NotificationCenter.default.removeObserver(selectionObservation)
            self.selectionObservation = nil
            whitespaceMarkers.selectedRanges = []
        }
        redrawWhitespace()
    }

    /// カーソルを動かしただけなら何もしない
    private func selectionDidChange() {
        let ranges = textView.nonEmptySelectedRanges
        guard ranges != whitespaceMarkers.selectedRanges else { return }
        whitespaceMarkers.selectedRanges = ranges
        redrawWhitespace()
    }

    /// NSTextViewは、見えている段落をそれぞれサブビューに描いて残し、描画用の属性やレイアウトを無効にしても描き直さないので、サブビューに描き直させる
    private func redrawWhitespace() {
        func setNeedsDisplay(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(setNeedsDisplay)
        }
        setNeedsDisplay(textView)
    }

    private func applyLineNumbers(of settings: EditorSettings) {
        if settings.showsLineNumbers, lineNumberView == nil {
            let lineNumberView = LineNumberView(textView: textView)
            container.addSubview(lineNumberView, positioned: .above, relativeTo: scrollView)
            self.lineNumberView = lineNumberView
        } else if !settings.showsLineNumbers {
            lineNumberView?.removeFromSuperview()
            lineNumberView = nil
        }
        lineNumberView?.fontSize = settings.fontSize
    }

    private func applyToolbar(of settings: EditorSettings) {
        let kinds = settings.enabledToolbarItems
        if kinds != toolbar?.kinds ?? [] {
            toolbar = kinds.isEmpty ? nil : EditorToolbar(kinds: kinds, textView: textView)
            editorWindow.toolbar = toolbar?.toolbar
        }
        toolbar?.kindsIgnoringSelection = settings.toolbarItemsIgnoringSelection
        measureTitlebar()
    }

    private func applyStatusBar(of settings: EditorSettings) {
        guard settings.showsStatusBarSettingsButton || !settings.enabledStatusBarItems.isEmpty else {
            statusBar?.removeFromSuperview()
            statusBar = nil
            return
        }
        let statusBar = statusBar ?? makeStatusBar()
        statusBar.update(with: settings)
        self.statusBar = statusBar
    }

    private func makeStatusBar() -> StatusBar {
        let statusBar = StatusBar(textView: textView)
        statusBar.fileEncodingName = fileEncoding.name
        statusBar.lineEndingName = lineEnding.name
        statusBar.backgroundColor = theme?.background
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusBar)
        NSLayoutConstraint.activate([
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBar.height),
        ])
        return statusBar
    }

    /// TextKit 2が組む、行間を含まない1行の高さを求める
    private static let metrics = NSLayoutManager()

    /// scrollableTextView()ではレイアウトマネージャーを差し替えられないので、同じ構成を自分で組む
    private static func makeTextView() -> (NSTextView, LineHeightSegmentLayoutManager) {
        let layoutManager = LineHeightSegmentLayoutManager()
        let contentStorage = TrailingNewlineContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.delegate = ParagraphIndentRules.shared
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return (textView, layoutManager)
    }

    private static func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.textContainer?.lineFragmentPadding = 0

        // 打鍵のたびに走る自動処理を切る
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .none
    }
}

extension EditorWindowController {
    private func titlebarDidChange() {
        guard measureTitlebar() else { return }
        updateInsets()
    }

    /// 高さが変わったかを返す
    @discardableResult
    private func measureTitlebar() -> Bool {
        guard !editorWindow.styleMask.contains(.fullScreen) else { return false }
        let height = editorWindow.frame.height - editorWindow.contentLayoutRect.height
        guard height != titlebarHeight else { return false }
        titlebarHeight = height
        return true
    }

    /// スクロールバーの出し方を変えたときも本文の幅が変わるので、ウィンドウではなくクリップビューを見張る
    private func observeClipViewFrame(_ observes: Bool) {
        if observes {
            // ウィンドウの大きさが変わるのはメインスレッドだけなので、通知もメインスレッドで届く
            clipViewFrameObservation = clipViewFrameObservation ?? NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateInsets() }
            }
        } else if let clipViewFrameObservation {
            NotificationCenter.default.removeObserver(clipViewFrameObservation)
            self.clipViewFrameObservation = nil
        }
    }

    /// ステータスバーの項目と歯車のアイコンを、本文の左右の端に揃える
    private func updateInsets() {
        guard let settings else { return }
        let fontSize = settings.fontSize
        let clipWidth = scrollView.contentView.frame.width
        let (leadingInset, trailingInset) = settings.horizontalInsets(clipWidth: clipWidth)
        let verticalExpansion = min((trailingInset - settings.minimumInset) / 2, fontSize * 4).rounded(.down)
        textView.setHorizontalInsets(leading: leadingInset, trailing: trailingInset, clipWidth: clipWidth)
        let gutter = settings.lineNumberWidth
        lineNumberView?.frame = NSRect(x: leadingInset - gutter, y: 0, width: gutter, height: container.bounds.height)
        statusBar?.leadingInset = leadingInset
        statusBar?.trailingInset = trailingInset
        let statusBarHeight = statusBar == nil ? 0 : StatusBar.height
        setContentInsets(NSEdgeInsets(
            top: titlebarHeight + fontSize + verticalExpansion,
            left: 0,
            bottom: max(statusBarHeight, fontSize) + fontSize + verticalExpansion,
            right: 0
        ))
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: statusBarHeight, right: 0)
    }

    /// クリップビューは余白を変えてもスクロールの位置を保つので、文書の先頭か末尾を見ているときは、変えた余白が見えるよう端に合わせ直す
    private func setContentInsets(_ insets: NSEdgeInsets) {
        let clipView = scrollView.contentView
        let previous = clipView.contentInsets
        guard previous.top != insets.top || previous.bottom != insets.bottom else { return }
        let visible = clipView.bounds
        let isAtTop = visible.minY <= -previous.top
        let isAtBottom = visible.maxY >= textView.frame.height + previous.bottom
        clipView.contentInsets = insets
        let originY: CGFloat
        if isAtTop {
            originY = -insets.top
        } else if isAtBottom {
            originY = textView.frame.height + insets.bottom - visible.height
        } else {
            return
        }
        clipView.scroll(to: NSPoint(x: visible.minX, y: originY))
        scrollView.reflectScrolledClipView(clipView)
    }
}

extension EditorWindowController: NSTextViewDelegate {
    /// applyFont(of:)とapplyTheme(_:)が本文全体に付ける属性
    private static let formattingKeys: [NSAttributedString.Key] = [.font, .paragraphStyle, .kern, .foregroundColor]

    /// NSTextViewは、改行キーでいつも\nを入れる
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard lineEnding != .lf,
              selector == #selector(NSResponder.insertNewline(_:))
              || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        else { return false }
        textView.insertText(lineEnding.rawValue, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    /// 状態の復元で後ろに開いたウィンドウでは気づけないので、ウィンドウがキーになるまで待つ
    func noticeMixedLineEndings() {
        needsMixedLineEndingNotice = true
        presentMixedLineEndingNoticeIfNeeded()
    }

    func windowDidBecomeKey(_: Notification) {
        presentMixedLineEndingNoticeIfNeeded()
    }

    private func presentMixedLineEndingNoticeIfNeeded() {
        guard needsMixedLineEndingNotice, editorWindow.isKeyWindow, editorWindow.attachedSheet == nil else { return }
        needsMixedLineEndingNotice = false
        let suppressionKey = "suppressesMixedLineEndingNotice"
        guard !UserDefaults.standard.bool(forKey: suppressionKey) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.mixedLineEndings.title")
        alert.informativeText = String(localized: "alert.mixedLineEndings.message \(lineEnding.name)")
        alert.showsSuppressionButton = true
        alert.beginSheetModal(for: editorWindow) { _ in
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: suppressionKey)
            }
        }
    }

    @objc private func undoManagerDidChange(_ notification: Notification) {
        guard let undoManager = (document as? NSDocument)?.undoManager,
              notification.object as? UndoManager === undoManager
        else { return }
        normalizeFormatting()
    }

    /// 取り消しとやり直しは、消した時点の属性ごと文字を戻すので、そのあとに設定を変えていたら、今の書式に直す
    /// 属性の変更なので、TextStoreは記録せず、取り消しの履歴にも入らない
    private func normalizeFormatting() {
        // 変換中は、入力する文字の属性が設定の書式と異なることがある
        guard !textView.hasMarkedText(), let storage = textView.textStorage, storage.length > 0 else { return }
        let current = textView.typingAttributes
        var staleRanges: [NSRange] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            let isStale = Self.formattingKeys.contains { key in
                attributes[key] as? NSObject != current[key] as? NSObject
            }
            if isStale {
                staleRanges.append(range)
            }
        }
        guard !staleRanges.isEmpty else { return }
        storage.beginEditing()
        for range in staleRanges {
            for key in Self.formattingKeys {
                if let value = current[key] {
                    storage.addAttribute(key, value: value, range: range)
                } else {
                    storage.removeAttribute(key, range: range)
                }
            }
        }
        storage.endEditing()
    }
}

extension NSTextView {
    var nonEmptySelectedRanges: [NSRange] {
        selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
    }

    /// 変換中の文字は本文にはないので、本文を書き換える前に捨てる
    func discardMarkedTextIfNeeded() {
        if hasMarkedText() {
            inputContext?.discardMarkedText()
        }
    }
}
