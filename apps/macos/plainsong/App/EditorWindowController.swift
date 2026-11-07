import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let editorWindow: NSWindow
    /// ステータスバーを本文に重ねるための入れ物。NSScrollViewは、サブビューにAuto Layoutの結果を反映しない
    let container = NSView()
    let scrollView = NSScrollView()
    let textView: NSTextView
    let layoutManager: LineHeightSegmentLayoutManager
    /// レイアウトマネージャーはデリゲートを弱参照で持つので、ここで持っておく
    let whitespaceMarkers = WhitespaceMarkers()
    let markdownHighlighter: MarkdownHighlighter
    let typesetter: JapaneseTypesetter
    private var selectionObservation: (any NSObjectProtocol)?
    private var clipViewFrameObservation: (any NSObjectProtocol)?
    /// ツールバーを含む高さ。全画面でタイトルバーが隠れても余白が変わらないよう、全画面のあいだは測り直さない
    private var titlebarHeight: CGFloat = 0
    private var titlebarObservation: NSKeyValueObservation?
    private var settings: EditorSettings?
    private var toolbar: EditorToolbar?
    private var statusBar: StatusBar?
    private var lineNumberView: LineNumberView?
    var manuscriptGridView: ManuscriptGridView?
    var ruledLinesView: RuledLinesView?
    var theme: Theme?
    /// 「デフォルト」とテーマにないキーは、NSTextViewが最初に持っている選択範囲の色に戻す
    private let standardSelectedTextAttributes: [NSAttributedString.Key: Any]
    var fileEncoding = FileEncoding.utf8 {
        didSet { statusBar?.fileEncodingName = fileEncoding.name }
    }

    var lineEnding = LineEnding.lf {
        didSet { statusBar?.lineEndingName = lineEnding.name }
    }

    var needsMixedLineEndingNotice = false

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
        markdownHighlighter = MarkdownHighlighter(textView: textView)
        typesetter = JapaneseTypesetter(textView: textView)
        standardSelectedTextAttributes = textView.selectedTextAttributes
        super.init(window: editorWindow)
        markdownHighlighter.didProcessEdits = { [weak typesetter] range in typesetter?.typeset(range) }
        editorWindow.delegate = self
        editorWindow.titleVisibility = .hidden
        editorWindow.titlebarAppearsTransparent = true
        editorWindow.titlebarSeparatorStyle = .none
        editorWindow.isReleasedWhenClosed = false
        place()

        layoutManager.delegate = whitespaceMarkers
        scrollView.contentView = EditorClipView()
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
    /// ファイルの名前が変わるたびに呼ばれるので、MDXかどうかもここで決め直す
    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        editorWindow.titleVisibility = (document as? NSDocument)?.fileURL == nil ? .hidden : .visible
        if markdownFlavor != markdownHighlighter.flavor {
            applyMarkdown()
        }
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
        let orientationChanged = settings.orientation != previous?.orientation ?? .horizontal
        if orientationChanged {
            textView.discardMarkedTextIfNeeded()
            textView.setLayoutOrientation(settings.orientation.layoutOrientation)
        }
        // 縦書きと原稿用紙では、立てる英数に差し替えた和文のフォントの行間で行送りが広がるので、フォントの行間を使わない
        // 横書きでは、使わないと明朝体のベースラインがずれる
        let usesFontLeading = settings.orientation == .horizontal && !settings.showsManuscriptGuide
        if layoutManager.usesFontLeading != usesFontLeading {
            layoutManager.usesFontLeading = usesFontLeading
        }
        let typesettingChanged = settings.fontFamily != previous?.fontFamily
            || settings.fontSize != previous?.fontSize
            || settings.lineSpacing != previous?.lineSpacing
            || settings.usesKerning != previous?.usesKerning
            || settings.addsParagraphSpacing != previous?.addsParagraphSpacing
            || settings.paragraphSpacing != previous?.paragraphSpacing
            || settings.indentsParagraphs != previous?.indentsParagraphs
            || settings.paragraphIndent != previous?.paragraphIndent
            || settings.usesReadableWidth != previous?.usesReadableWidth
            || settings.showsLineNumbers != previous?.showsLineNumbers
            || settings.guide != previous?.guide
        if typesettingChanged {
            if let container = textView.textContainer as? ManuscriptTextContainer {
                // マス数はウィンドウの大きさで決まるので、`updateInsets()`で渡す
                if !settings.showsManuscriptGuide {
                    container.paper = nil
                }
                container.cellWidth = settings.fontSize
            }
            applyFont(of: settings)
        }
        // 起動して「デフォルト」のままなら、システムの色のままなので何もしない
        let themeChanged = settings.theme != previous?.theme ?? .standard
        if themeChanged {
            applyTheme(ThemeLibrary().theme(for: settings.theme))
        }
        let highlightingChanged = settings.highlightsMarkdown != previous?.highlightsMarkdown
        if typesettingChanged || themeChanged || orientationChanged || highlightingChanged {
            applyMarkdown()
        }
        applyWhitespace(of: settings)
        applyLineNumbers(of: settings)
        applyManuscriptGrid(of: settings)
        applyRuledLines(of: settings)
        observeClipViewFrame(
            settings.usesReadableWidth || settings.showsManuscriptGuide
                || settings.showsLineNumbers || settings.orientation == .vertical
        )
        applyToolbar(of: settings)
        applyStatusBar(of: settings)
        updateInsets()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// 本文全体を1回の編集で書き換える。属性の変更なので、TextStoreは記録せず、取り消しの履歴にも入らない
    private func applyFont(of settings: EditorSettings) {
        let bodyFont = settings.fontFamily.font(ofSize: settings.fontSize)
        let lineHeight = Self.lineHeight(of: settings)
        let paragraphStyle = settings.paragraphStyle(lineHeight: lineHeight)
        layoutManager.lineHeight = lineHeight
        let japanese = EditorSettings.japaneseFont(for: bodyFont)
        layoutManager.japaneseMiddle = (japanese.ascender + japanese.descender) / 2
        let font = settings.bodyFont

        // defaultParagraphStyleは、変換を通さずに入力した文字には付かないので、入力する文字の属性に指定する
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes(
                [.font: font, .paragraphStyle: paragraphStyle],
                range: NSRange(location: 0, length: storage.length)
            )
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
        manuscriptGridView?.color = theme?.foreground ?? .labelColor
        ruledLinesView?.color = theme?.foreground ?? .labelColor
        whitespaceMarkers.color = theme?.foreground.map { $0.withAlphaComponent(0.3) } ?? .tertiaryLabelColor
        if whitespaceMarkers.scope != nil || whitespaceMarkers.showsNewlines {
            redrawText()
        }
    }

    private var markdownFlavor: MarkdownSyntax.Flavor? {
        // 原稿用紙では、記法で変えたフォントや字下げがマスからずれる
        guard let settings, settings.highlightsMarkdown, !settings.showsManuscriptGuide else { return nil }
        return MarkdownSyntax.Flavor(url: (document as? NSDocument)?.fileURL)
    }

    /// `applyFont(of:)`と`applyTheme(_:)`が本文全体のフォントと色を上書きするので、そのあとに呼び直す
    /// 記法で変えたフォントも立てる英数のフォントに差し替えるので、そのあとに組み直す
    private func applyMarkdown() {
        guard let settings else { return }
        markdownHighlighter.update(flavor: markdownFlavor, appearance: .init(settings: settings, theme: theme))
        typesetter.update(
            usesKerning: settings.usesKerning && !settings.showsManuscriptGuide,
            isVertical: settings.orientation == .vertical,
            manuscriptFont: settings.showsManuscriptGuide ? settings.bodyFont : nil
        )
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
        redrawText()
    }

    /// カーソルを動かしただけなら何もしない
    private func selectionDidChange() {
        let ranges = textView.nonEmptySelectedRanges
        guard ranges != whitespaceMarkers.selectedRanges else { return }
        whitespaceMarkers.selectedRanges = ranges
        redrawText()
    }

    /// NSTextViewは、見えている段落をそれぞれサブビューに描いて残し、描画用の属性やレイアウトを無効にしても描き直さないので、サブビューに描き直させる
    func redrawText() {
        func setNeedsDisplay(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(setNeedsDisplay)
        }
        setNeedsDisplay(textView)
    }

    private func applyToolbar(of settings: EditorSettings) {
        let kinds = settings.enabledToolbarItems
        if kinds != toolbar?.kinds ?? [] {
            toolbar = kinds.isEmpty ? nil : EditorToolbar(kinds: kinds, textView: textView)
            editorWindow.toolbar = toolbar?.toolbar
        }
        toolbar?.kindsIgnoringSelection = settings.toolbarItemsIgnoringSelection
        toolbar?.findOpensReplace = settings.toolbarFindOpensReplace
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
        let clipSize = scrollView.contentView.frame.size
        let statusBarHeight = statusBar == nil ? 0 : StatusBar.height
        let topInset = titlebarHeight + fontSize
        let bottomInset = max(statusBarHeight, fontSize) + fontSize
        let isVertical = settings.orientation == .vertical
        let clipLength = isVertical ? clipSize.height : clipSize.width
        let gutter = settings.lineNumberGutter
        let baseLeading = isVertical ? topInset : settings.minimumInset
        let minimumLeading = settings.showsLineNumbers ? baseLeading + gutter / 2 : baseLeading
        let minimumTrailing = isVertical ? bottomInset : settings.minimumInset
        if settings.showsManuscriptGuide {
            applyManuscriptCells(settings.manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            ), of: settings)
        }
        let (leading, trailing) = settings.lineInsets(
            clipLength: clipLength,
            minimumLeading: minimumLeading,
            minimumTrailing: minimumTrailing
        )
        let expansion = settings.crossInsetExpansion(
            clipLength: clipLength,
            minimumLeading: minimumLeading,
            minimumTrailing: minimumTrailing
        )
        lineNumberView?.frame = isVertical
            ? NSRect(x: 0, y: container.bounds.height - leading, width: container.bounds.width, height: gutter)
            : NSRect(x: leading - gutter, y: 0, width: gutter, height: container.bounds.height)
        let sideInset = settings.minimumInset + expansion
        statusBar?.leadingInset = isVertical ? sideInset : leading
        statusBar?.trailingInset = isVertical ? sideInset : trailing
        // 縦書きでは上の余白もクリップビューで空ける。テキストコンテナで空けると、テキストビューがタイトルバーに重なってウィンドウをつかめなくなる
        // 下の余白はテキストコンテナで空ける。テキストビューの外には描けないので、クリップビューで空けると行末の改行の記号が切れる
        let overhang = LineHeightSegmentLayoutManager.bandOverhang
        let clipInsets = isVertical
            ? NSEdgeInsets(top: topInset, left: sideInset - overhang, bottom: 0, right: sideInset - overhang)
            : NSEdgeInsets(
                top: topInset + expansion - overhang,
                left: 0,
                bottom: bottomInset + expansion - overhang,
                right: 0
            )
        let before = isVertical ? clipInsets.top : 0
        textView.setLineInsets(leading: leading - before, trailing: trailing, clipLength: clipLength - before)
        // 大きさが0のウィンドウで縦書きに組むと、テキストビューの原点が行末の余白の分だけずれ、横書きに切り替えても残る
        if textView.frame.origin != .zero {
            textView.setFrameOrigin(.zero)
        }
        setContentInsets(clipInsets)
        manuscriptGridView?.needsDisplay = true
        ruledLinesView?.needsDisplay = true
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: statusBarHeight, right: 0)
    }

    /// クリップビューは余白を変えてもスクロールの位置を保つので、文書の先頭か末尾を見ているときは、変えた余白が見えるよう端に合わせ直す
    private func setContentInsets(_ insets: NSEdgeInsets) {
        let clipView = scrollView.contentView
        let previous = clipView.contentInsets
        guard (previous.top, previous.left, previous.bottom, previous.right)
            != (insets.top, insets.left, insets.bottom, insets.right)
        else { return }
        let visible = clipView.bounds
        let size = textView.frame.size
        var origin = visible.origin
        if textView.layoutOrientation == .vertical {
            origin.y = -insets.top
            if visible.maxX >= size.width + previous.right {
                origin.x = size.width + insets.right - visible.width
            } else if visible.minX <= -previous.left {
                origin.x = -insets.left
            }
        } else if visible.minY <= -previous.top {
            origin.y = -insets.top
        } else if visible.maxY >= size.height + previous.bottom {
            origin.y = size.height + insets.bottom - visible.height
        }
        clipView.contentInsets = insets
        guard origin != visible.origin else { return }
        clipView.scroll(to: clipView.constrainBoundsRect(NSRect(origin: origin, size: visible.size)).origin)
        scrollView.reflectScrolledClipView(clipView)
    }
}
