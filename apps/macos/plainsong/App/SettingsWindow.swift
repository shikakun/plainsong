import AppKit

/// 設定ウィンドウ
final class SettingsWindowController: NSWindowController {
    private static let frameName = "Settings"

    convenience init(model: SettingsModel, relaunch: @escaping () -> Void) {
        let tabViewController = SettingsTabViewController()
        tabViewController.tabStyle = .toolbar
        // ウインドウメニューに出す名前と合わせて、タイトルは自分で更新する
        tabViewController.canPropagateSelectedChildViewControllerTitle = false
        tabViewController.tabViewItems = [
            Self.tab(GeneralSettingsPane(model: model, relaunch: relaunch), symbol: "gear"),
            Self.tab(ThemeSettingsPane(model: model), symbol: "paintpalette"),
            Self.tab(ExtensionsSettingsPane(model: model), symbol: "puzzlepiece.extension"),
        ]
        tabViewController.restoreSelectedTab()

        let window = NSWindow(contentViewController: tabViewController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        Self.restorePosition(of: window)
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        (contentViewController as? SettingsTabViewController)?.updateWindowTitle()
    }

    /// ⎋キーと⌘.で閉じる。キー入力を受けるビューがないと、ウィンドウはcancelOperation(_:)ではなくcancel:を送る
    @objc func cancel(_: Any?) {
        close()
    }

    private static func tab(_ pane: NSViewController, symbol: String) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: pane)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    /// 大きさはペインの内容で決まるので、保存した位置だけを使う
    private static func restorePosition(of window: NSWindow) {
        let size = window.frame.size
        if window.setFrameUsingName(frameName) {
            let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - size.height)
            window.setFrame(NSRect(origin: origin, size: size), display: false)
        } else {
            window.center()
        }
        window.setFrameAutosaveName(frameName)
    }
}

private final class SettingsTabViewController: NSTabViewController {
    private static let selectedTabKey = "settingsSelectedTab"

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.selectedTabKey)
        updateWindowTitle()
    }

    func restoreSelectedTab() {
        let index = UserDefaults.standard.integer(forKey: Self.selectedTabKey)
        if tabViewItems.indices.contains(index) {
            selectedTabViewItemIndex = index
        }
    }

    func updateWindowTitle() {
        guard let window = tabView.window, let label = tabView.selectedTabViewItem?.label else { return }
        window.title = label
        // タイトルを変えるとAppKitがウインドウメニューの項目を書き換えるので、そのあとに変える
        if window.isVisible {
            NSApp.changeWindowsItem(window, title: "\(String(localized: "settings.title")) — \(label)", filename: false)
        }
    }
}

final class SettingsModel {
    static let didChangeNotification = Notification.Name("SettingsModelDidChange")

    private(set) var settings: EditorSettings
    private let onChange: (EditorSettings) -> Void

    init(settings: EditorSettings, onChange: @escaping (EditorSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    func update(_ change: (inout EditorSettings) -> Void) {
        var settings = settings
        change(&settings)
        guard settings != self.settings else { return }
        self.settings = settings
        onChange(settings)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

/// ガイドラインにある最小の高さは設けず、高さを内容に合わせる
class SettingsPane: NSViewController {
    private static let minimumWidth: CGFloat = 530
    private static let margin: CGFloat = 20
    /// セクションを積む入れ物。ビューにはpreferredContentSizeと同じ大きさの制約が付いてfittingSizeが縮まなくなるので、こちらを測る
    private let content = NSView()

    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override func loadView() {
        let view = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        var constraints = [
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
        ]
        let sections = makeSections()
        var top = content.topAnchor
        for section in sections {
            section.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(section)
            constraints.append(section.topAnchor.constraint(equalTo: top, constant: Self.margin))
            if section is GroupSection || (section as? NSBox)?.boxType == .separator {
                constraints += [
                    section.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.margin),
                    content.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: Self.margin),
                ]
            } else {
                constraints += [
                    section.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                    section.leadingAnchor.constraint(
                        greaterThanOrEqualTo: content.leadingAnchor,
                        constant: Self.margin
                    ),
                ]
            }
            top = section.bottomAnchor
        }
        constraints.append(content.bottomAnchor.constraint(
            equalTo: top,
            constant: sections.isEmpty ? Self.margin * 2 : Self.margin
        ))
        NSLayoutConstraint.activate(constraints)
        self.view = view
        updatePreferredContentSize()
    }

    func makeSections() -> [NSView] {
        []
    }

    func updatePreferredContentSize() {
        preferredContentSize = content.fittingSize
    }

    static func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: "\(title):")
        label.lineBreakMode = .byTruncatingMiddle
        label.allowsExpansionToolTips = true
        return label
    }

    static func columns(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 8
        grid.rowSpacing = 20
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 1).width = 260
        return grid
    }

    static func alignLabelColumns(_ grids: [NSGridView]) {
        let labels = grids.flatMap { grid in
            (0 ..< grid.numberOfRows).compactMap { grid.cell(atColumnIndex: 0, rowIndex: $0).contentView }
        }
        let width = labels.map(\.fittingSize.width).max() ?? 0
        for grid in grids {
            grid.column(at: 0).width = width
        }
    }

    static func note(_ text: String) -> NSTextField {
        let note = NSTextField(wrappingLabelWithString: text)
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        return note
    }

    static func linkButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.contentTintColor = .linkColor
        return button
    }

    static func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
}

final class GroupSection: NSStackView {
    init(title: String?, content: NSView, footer: [NSView] = []) {
        super.init(frame: .zero)
        let heading = title.map { title in
            let heading = NSTextField(labelWithString: title)
            heading.font = .preferredFont(forTextStyle: .headline)
            return heading
        }

        let box = NSBox()
        box.titlePosition = .noTitle
        box.contentViewMargins = .zero
        if let boxContent = box.contentView {
            content.translatesAutoresizingMaskIntoConstraints = false
            boxContent.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: boxContent.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: boxContent.trailingAnchor),
                content.topAnchor.constraint(equalTo: boxContent.topAnchor),
                content.bottomAnchor.constraint(equalTo: boxContent.bottomAnchor),
            ])
        }

        orientation = .vertical
        alignment = .leading
        spacing = 6
        setViews([heading, box].compactMap(\.self) + footer, in: .top)
        box.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }
}

final class SettingsSheetController: NSWindowController {
    private static let margin: CGFloat = 20

    convenience init(title: String, content: NSView) {
        let doneButton = NSButton(title: String(localized: "settings.done"), target: nil, action: nil)
        doneButton.keyEquivalent = "\r"
        let view = NSView()
        for subview in [content, doneButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.margin),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: content.trailingAnchor, constant: Self.margin),
            doneButton.topAnchor.constraint(equalTo: content.bottomAnchor, constant: Self.margin),
            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Self.margin),
            view.trailingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: Self.margin),
            view.bottomAnchor.constraint(equalTo: doneButton.bottomAnchor, constant: Self.margin),
        ])
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        // シートにタイトルは出ないが、VoiceOverで読まれる
        window.title = title
        window.contentView = view
        window.setContentSize(view.fittingSize)
        self.init(window: window)
        doneButton.target = self
        doneButton.action = #selector(cancel(_:))
    }

    /// シートを閉じるまで、このコントローラーを解放させない
    func begin(for parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window) { _ in
            withExtendedLifetime(self) {}
        }
    }

    /// ⎋キーと⌘.で閉じる。キー入力を受けるビューがないと、ウィンドウはcancelOperation(_:)ではなくcancel:を送る
    @objc func cancel(_: Any?) {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window)
    }

    /// シートの中のテキストビューがキー入力を受けていると、⎋キーで`cancel:`ではなくこちらが呼ばれる
    override func cancelOperation(_ sender: Any?) {
        cancel(sender)
    }
}
