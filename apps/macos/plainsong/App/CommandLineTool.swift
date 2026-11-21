import AppKit

enum CommandLineTool {
    static let name = "song"
    private static let linkDirectory = "/usr/local/bin"
    private static var linkPath: String {
        "\(linkDirectory)/\(name)"
    }

    static func installCommand(toolPath: String) -> String {
        "sudo mkdir -p \(linkDirectory) && sudo ln -si \(shellQuoted(toolPath)) \(linkPath) && \(name) --help"
    }

    static var uninstallCommand: String {
        "sudo rm \(linkPath)"
    }

    static func shellQuoted(_ text: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+@%:,"))
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(safe.contains) else {
            return "'\(text.replacing("'", with: #"'\''"#))'"
        }
        return text
    }
}

final class CommandLineToolWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentViewController: CommandLineToolViewController())
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        // タイトルは画面に出さないが、VoiceOverの読み上げとウインドウメニューに使われる
        window.title = String(localized: "commandLineTool.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    @objc func cancel(_: Any?) {
        close()
    }

    /// コマンドの文字を選択していると、⎋キーで`cancel:`ではなくこちらが呼ばれる
    override func cancelOperation(_ sender: Any?) {
        cancel(sender)
    }
}

private final class CommandLineToolViewController: NSViewController {
    /// 設定ウィンドウと同じ幅と余白にする
    private static let width: CGFloat = 530
    private static let margin: CGFloat = 20
    private static let iconSize: CGFloat = 64
    /// アプリのアイコンは、1024pxの枠の上下左右に100pxの余白を空けて描かれている
    private static let iconInset = iconSize * 100 / 1024
    private static let copiedDuration: Duration = .seconds(2)
    private var commands: [NSButton: String] = [:]
    private var restoreTasks: [NSButton: Task<Void, Never>] = [:]

    override func loadView() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.setAccessibilityElement(false)
        let heading = NSTextField(labelWithString: String(localized: "commandLineTool.heading"))
        heading.font = .boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize)
        let description = NSTextField(wrappingLabelWithString: "")
        description.attributedStringValue = Self.description()
        // 選択できると、クリックしたときに表示がフィールドエディタに替わり、行間と文字色が外れる
        description.isSelectable = false
        let texts = NSStackView(views: [heading, description])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 4

        let toolPath = Bundle.main.bundleURL.appending(path: "Contents/SharedSupport/bin/\(CommandLineTool.name)").path
        let install = section(
            title: String(localized: "commandLineTool.install"),
            command: CommandLineTool.installCommand(toolPath: toolPath)
        )
        let uninstall = section(
            title: String(localized: "commandLineTool.uninstall"),
            command: CommandLineTool.uninstallCommand
        )

        let view = NSView()
        for subview in [icon, texts, install, uninstall] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        // アイコンと説明文のうち、下にあるほうから余白を空ける
        let pullsUp = install.topAnchor.constraint(equalTo: texts.bottomAnchor, constant: Self.margin)
        pullsUp.priority = .defaultLow
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.width),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
            icon.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
            // 見出しの行の上端を、アイコンの絵の上端に揃える
            texts.topAnchor.constraint(equalTo: icon.topAnchor, constant: Self.iconInset),
            texts.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: texts.trailingAnchor, constant: Self.margin),
            install.topAnchor.constraint(greaterThanOrEqualTo: texts.bottomAnchor, constant: Self.margin),
            install.topAnchor.constraint(
                greaterThanOrEqualTo: icon.bottomAnchor,
                constant: Self.margin - Self.iconInset
            ),
            pullsUp,
            uninstall.topAnchor.constraint(equalTo: install.bottomAnchor, constant: Self.margin),
            view.bottomAnchor.constraint(equalTo: uninstall.bottomAnchor, constant: Self.margin),
        ])
        for section in [install, uninstall] {
            NSLayoutConstraint.activate([
                section.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
                view.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: Self.margin),
            ])
        }
        self.view = view
    }

    /// 標準の行間では詰まって見えるので、一段階広げる
    private static func description() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        return NSAttributedString(string: String(localized: "commandLineTool.description"), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    private func section(title: String, command: String) -> GroupSection {
        let text = NSTextField(wrappingLabelWithString: command)
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        text.isSelectable = true
        text.setAccessibilityLabel(title)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = NSButton(
            title: String(localized: "commandLineTool.copied"),
            target: self,
            action: #selector(copyCommand(_:))
        )
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        // 「コピーしました」に変わっても並びが動かないよう、長いほうの文言に幅を合わせる
        let width = button.fittingSize.width
        button.title = String(localized: "commandLineTool.copy")
        button.widthAnchor.constraint(equalToConstant: max(width, button.fittingSize.width)).isActive = true
        // 2つのボタンの名前が同じなので、VoiceOverではどちらのコマンドかを添える
        button.setAccessibilityLabel(String(localized: "commandLineTool.copy \(title)"))
        commands[button] = command

        let grid = NSGridView(views: [[text, button]])
        grid.columnSpacing = 12
        grid.rowAlignment = .firstBaseline
        // 短いコマンドでも、余った幅の右端にボタンを置く
        grid.column(at: 1).xPlacement = .trailing
        let content = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: grid.trailingAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
        ])
        return GroupSection(title: title, content: content)
    }

    @objc private func copyCommand(_ sender: NSButton) {
        guard let command = commands[sender] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let copied = String(localized: "commandLineTool.copied")
        sender.title = copied
        NSAccessibility.post(
            element: sender,
            notification: .announcementRequested,
            userInfo: [.announcement: copied, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        restoreTasks[sender]?.cancel()
        restoreTasks[sender] = Task {
            try? await Task.sleep(for: Self.copiedDuration)
            guard !Task.isCancelled else { return }
            sender.title = String(localized: "commandLineTool.copy")
        }
    }
}
