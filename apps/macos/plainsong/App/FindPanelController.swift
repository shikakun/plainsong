import AppKit

/// 起動を軽くするため、パネルは初めて開くまで作らない
final class FindPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    static let shared = FindPanelController()

    private static let wrapsAroundKey = "findWrapsAround"

    private var panel: FindPanel?
    private weak var editor: EditorWindowController?
    private var search = TextSearch.load(from: .standard)
    private var template = ""
    private var wrapsAround: Bool
    private var results: [TextSearch.Match] = []
    private var isInvalidPattern = false
    private var flow: ReplaceFlow?
    private var outcome: FindOutcome?
    private var markedRanges: [NSRange] = []
    private var findPasteboard = FindPasteboard()
    private var refreshTask: Task<Void, Never>?
    private var patternTask: Task<Void, Never>?

    override private init() {
        wrapsAround = UserDefaults.standard.object(forKey: Self.wrapsAroundKey) as? Bool ?? true
        super.init()
        for (name, selector) in [
            (NSWindow.didBecomeMainNotification, #selector(mainWindowDidChange(_:))),
            (NSWindow.willCloseNotification, #selector(anyWindowWillClose(_:))),
        ] {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    /// パネルを閉じていても、ほかのアプリで検索した語が検索用ペーストボードにあれば、次を検索できる
    var hasPattern: Bool {
        !search.pattern.isEmpty || FindPasteboard.hasString
    }

    var canReplaceAll: Bool {
        panel?.isVisible == true && panel?.mode == .replace && !results.isEmpty
    }

    private var currentIndex: Int? {
        guard let selection = editor?.findSelection else { return nil }
        return results.firstIndex { $0.range == selection }
    }

    func show(for editor: EditorWindowController, mode: FindPanel.Mode) {
        let panel = panel ?? makePanel(near: editor)
        readFindPasteboard()
        attach(editor)
        if panel.mode != mode {
            panel.mode = mode
            resetFlow()
        }
        panel.makeKeyAndOrderFront(nil)
        let field: NSTextField = mode == .find ? panel.findField : panel.replaceField
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        refresh(selectingFrom: editor.findSelection.location)
    }

    func move(in editor: EditorWindowController, backwards: Bool) {
        let isShown = panel?.isVisible == true
        if isShown {
            attach(editor)
        } else {
            readFindPasteboard()
        }
        let ranges = isShown ? results.map(\.range) : (try? search.matches(in: editor.findString))?.map(\.range) ?? []
        let navigation = FindNavigation(ranges: ranges, selection: editor.findSelection, stopsAtEdges: !wrapsAround)
        guard let target = navigation.target(backwards: backwards) else {
            NSSound.beep()
            return
        }
        if target.wrapped {
            flow?.didWrap(backwards: backwards)
        }
        editor.showFindResult(ranges[target.index], avoiding: isShown ? panel?.frame : nil)
        let isAtEdge = isShown && navigation.isAtEdge(target.index, backwards: backwards)
        outcome = isAtEdge ? (backwards ? .reachedStart : .reachedEnd(replaced: flow?.replacedCount ?? 0)) : nil
        updateControls()
        if let outcome {
            panel?.announce(outcome.message)
        }
    }

    func selectAllResults(in editor: EditorWindowController) {
        readFindPasteboard()
        guard let results = try? search.matches(in: editor.findString), !results.isEmpty else {
            NSSound.beep()
            return
        }
        editor.selectFindResults(results.map(\.range))
        updateControls()
    }

    func useSelection(of editor: EditorWindowController, forReplacement: Bool) {
        let selection = editor.findSelection
        guard selection.length > 0 else { return }
        let text = editor.findString.substring(with: selection)
        if forReplacement {
            template = search.usesRegularExpression ? NSRegularExpression.escapedTemplate(for: text) : text
            panel?.replaceField.stringValue = template
        } else {
            search.pattern = search.usesRegularExpression ? NSRegularExpression.escapedPattern(for: text) : text
            panel?.findField.stringValue = search.pattern
            findPasteboard.write(search.pattern)
        }
        resetFlow()
        if panel?.isVisible == true, editor === self.editor {
            refresh(selectingFrom: selection.location)
        }
    }

    private func makePanel(near editor: EditorWindowController) -> FindPanel {
        let panel = FindPanel()
        panel.delegate = self
        panel.findField.delegate = self
        panel.replaceField.delegate = self
        panel.findField.stringValue = search.pattern
        panel.replaceField.stringValue = template
        let actions: [(NSControl, Selector)] = [
            (panel.modeControl, #selector(modeDidChange(_:))),
            (panel.navigationControl, #selector(navigate(_:))),
            (panel.matchesCaseButton, #selector(optionDidChange(_:))),
            (panel.matchesWidthButton, #selector(optionDidChange(_:))),
            (panel.regularExpressionButton, #selector(optionDidChange(_:))),
            (panel.wrapsAroundButton, #selector(wrapsAroundDidChange(_:))),
            (panel.findNextButton, #selector(findNextPressed(_:))),
            (panel.replaceAndFindButton, #selector(replaceAndFind(_:))),
        ]
        for (control, action) in actions {
            control.target = self
            control.action = action
        }
        panel.replaceAllItem.target = self
        panel.replaceAllItem.action = #selector(replaceAll(_:))
        panel.matchesCaseButton.state = search.matchesCase ? .on : .off
        panel.regularExpressionButton.state = search.usesRegularExpression ? .on : .off
        panel.wrapsAroundButton.state = wrapsAround ? .on : .off
        panel.place(near: editor.window?.frame)
        self.panel = panel
        return panel
    }

    private func attach(_ editor: EditorWindowController) {
        panel?.applyAppearance(of: editor.window, background: editor.findBackground)
        guard editor !== self.editor else { return }
        detach()
        self.editor = editor
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: editor.textStorage
        )
    }

    private func detach() {
        guard let editor else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSTextStorage.didProcessEditingNotification,
            object: editor.textStorage
        )
        markedRanges = editor.updateFindMarks(removing: markedRanges, results: [], replaced: [])
        self.editor = nil
        results = []
        resetFlow()
    }

    private func resetFlow() {
        flow = nil
        outcome = nil
    }
}

extension FindPanelController {
    private func refresh(selectingFrom location: Int?) {
        guard let editor, let panel, panel.isVisible else { return }
        do {
            results = try search.matches(in: editor.findString).filter { flow?.excludes($0.range) != true }
            isInvalidPattern = false
        } catch {
            results = []
            isInvalidPattern = true
        }
        if let location, !results.isEmpty {
            let index = results.firstIndex { $0.range.location >= location } ?? 0
            editor.showFindResult(results[index].range, avoiding: panel.frame)
        }
        markedRanges = editor.updateFindMarks(
            removing: markedRanges,
            results: results.map(\.range),
            replaced: flow?.replaced ?? []
        )
        updateControls()
    }

    private func updateControls() {
        guard let panel else { return }
        let current = currentIndex
        if isInvalidPattern {
            panel.showCount(
                String(localized: "find.count.invalidPattern"),
                isError: true,
                accessibilityText: String(localized: "find.count.invalidPattern.detail")
            )
        } else if search.pattern.isEmpty {
            panel.showCount("")
        } else if results.isEmpty {
            panel.showCount(String(localized: "find.count.notFound"))
        } else if let current {
            panel.showCount(String(localized: "find.count.position \(current + 1) \(results.count)"))
        } else {
            panel.showCount(String(localized: "find.count.total \(results.count)"))
        }
        let navigation = FindNavigation(
            ranges: results.map(\.range),
            selection: editor?.findSelection ?? NSRange(),
            stopsAtEdges: !wrapsAround
        )
        let canGoForward = navigation.target(backwards: false) != nil
        panel.navigationControl.setEnabled(navigation.target(backwards: true) != nil, forSegment: 0)
        panel.navigationControl.setEnabled(canGoForward, forSegment: 1)
        panel.findNextButton.isEnabled = canGoForward
        panel.replaceAllItem.isEnabled = !results.isEmpty
        // 一致した箇所を選んでいないときは、置換せずに次の箇所を選ぶだけなので、次の箇所さえあれば押せるようにする
        panel.replaceAndFindButton.isEnabled = current != nil || canGoForward
        panel.matchesWidthButton.isEnabled = !search.usesRegularExpression
        panel.matchesWidthButton.state = search.usesRegularExpression || search.matchesWidth ? .on : .off
        panel.showStatus(outcome)
    }

    private func finish(_ outcome: FindOutcome, at location: Int) {
        self.outcome = outcome
        editor?.setFindSelection(NSRange(location: location, length: 0))
        updateControls()
        panel?.announce(outcome.message)
    }

    private func readFindPasteboard() {
        guard let string = findPasteboard.readChanges(), string != search.pattern else { return }
        search.pattern = string
        panel?.findField.stringValue = string
        resetFlow()
    }

    /// 検索欄の入力が止まるのを待っている途中でReturnやボタンが押されたら、待たずにすぐ探し直す。探し直したときはtrueを返す
    @discardableResult
    private func syncPattern() -> Bool {
        guard let field = panel?.findField, field.stringValue != search.pattern else { return false }
        patternDidChange(field)
        return true
    }
}

extension FindPanelController {
    private func patternDidChange(_ field: NSTextField) {
        guard field.stringValue != search.pattern else { return }
        search.pattern = field.stringValue
        findPasteboard.write(search.pattern)
        resetFlow()
        refresh(selectingFrom: editor?.findSelection.location)
    }

    @objc private func modeDidChange(_ sender: NSSegmentedControl) {
        guard let panel, let mode = FindPanel.Mode(rawValue: sender.selectedSegment) else { return }
        panel.mode = mode
        resetFlow()
        if mode == .replace {
            panel.makeFirstResponder(panel.replaceField)
        }
        refresh(selectingFrom: editor?.findSelection.location)
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        guard let editor else { return }
        syncPattern()
        move(in: editor, backwards: sender.selectedSegment == 0)
    }

    /// 入力が止まるのを待たずに探し直したときは、そこで選んだ箇所を次の箇所として扱い、さらに先へは進まない
    @objc private func findNextPressed(_: Any?) {
        guard let editor, !syncPattern() else { return }
        move(in: editor, backwards: false)
    }

    @objc private func optionDidChange(_ sender: NSButton) {
        guard let panel else { return }
        let isOn = sender.state == .on
        switch sender {
        case panel.matchesCaseButton:
            search.matchesCase = isOn
        case panel.matchesWidthButton:
            search.matchesWidth = isOn
        case panel.regularExpressionButton:
            search.usesRegularExpression = isOn
        default:
            return
        }
        search.save(to: .standard)
        resetFlow()
        refresh(selectingFrom: editor?.findSelection.location)
    }

    @objc private func wrapsAroundDidChange(_ sender: NSButton) {
        wrapsAround = sender.state == .on
        UserDefaults.standard.set(wrapsAround, forKey: Self.wrapsAroundKey)
        outcome = nil
        updateControls()
    }

    @objc private func replaceAndFind(_: Any?) {
        guard let editor, let panel else { return }
        syncPattern()
        guard let index = currentIndex else {
            move(in: editor, backwards: false)
            return
        }
        let match = results[index]
        let replacement = TextSearch.replacement(for: match, in: editor.findString, template: template)
        // 始めた箇所の位置は書き換えの通知を受けて合わせ直すので、書き換えるより先に流れを作っておく
        if flow == nil {
            flow = ReplaceFlow(start: match.range.location)
        } else if outcome != nil {
            flow?.restart(at: match.range.location)
        }
        guard let replaced = editor.replaceFindResults(
            [match.range],
            with: [replacement],
            actionName: String(localized: "find.undo.replace")
        )?.first else { return }
        flow?.record([replaced])
        refreshTask?.cancel()
        refresh(selectingFrom: nil)
        let from = NSMaxRange(replaced)
        let replacedCount = flow?.replacedCount ?? 1
        switch flow?.step(after: from, in: results.map(\.range), stopsAtEnd: !wrapsAround) {
        case let .select(next):
            editor.showFindResult(results[next].range, avoiding: panel.frame)
            outcome = nil
            updateControls()
        case .reachedEnd:
            finish(.reachedEnd(replaced: replacedCount), at: from)
        case .completed, nil:
            finish(.completed(replaced: replacedCount), at: from)
        }
    }

    func replaceAll(in editor: EditorWindowController) {
        guard canReplaceAll, editor === self.editor else {
            NSSound.beep()
            return
        }
        replaceAll(nil)
    }

    /// 置換の流れのなかですでに置換した箇所は、重ねて置換しない
    @objc private func replaceAll(_: Any?) {
        guard let editor else { return }
        syncPattern()
        refresh(selectingFrom: nil)
        guard !results.isEmpty else {
            NSSound.beep()
            return
        }
        let string = editor.findString
        let replacements = results.map { TextSearch.replacement(for: $0, in: string, template: template) }
        guard let replaced = editor.replaceFindResults(
            results.map(\.range),
            with: replacements,
            actionName: String(localized: "find.undo.replaceAll")
        ), let last = replaced.last else { return }
        var flow = flow ?? ReplaceFlow(start: 0)
        flow.record(replaced)
        self.flow = flow
        refreshTask?.cancel()
        refresh(selectingFrom: nil)
        finish(.replacedAll(replaced.count), at: NSMaxRange(last))
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let panel else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === panel.replaceField {
                replaceAndFind(nil)
            } else if !syncPattern(), let editor {
                move(in: editor, backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            panel.performClose(nil)
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let panel, let field = notification.object as? NSTextField else { return }
        guard field === panel.replaceField else {
            patternTask?.cancel()
            patternTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.syncPattern()
            }
            return
        }
        template = field.stringValue
        guard flow != nil || outcome != nil else { return }
        resetFlow()
        refresh(selectingFrom: nil)
    }

    func windowWillClose(_: Notification) {
        detach()
    }

    @objc private func mainWindowDidChange(_ notification: Notification) {
        guard panel?.isVisible == true,
              let editor = (notification.object as? NSWindow)?.windowController as? EditorWindowController,
              editor !== self.editor
        else { return }
        attach(editor)
        refresh(selectingFrom: nil)
    }

    @objc private func anyWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === editor?.window else { return }
        detach()
        updateControls()
    }

    @objc private func textDidProcessEditing(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters)
        else { return }
        let edited = storage.editedRange
        let delta = storage.changeInLength
        markedRanges = markedRanges.map { $0.resized(forEditIn: edited, changeInLength: delta) }
        flow?.adjust(forEditIn: edited, changeInLength: delta)
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.refresh(selectingFrom: nil)
        }
    }
}
