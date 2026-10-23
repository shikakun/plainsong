import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var menuBarIcon: MenuBarIcon?
    private var settingsWindowController: SettingsWindowController?
    /// 最初に作ったインスタンスが`NSDocumentController.shared`になるので、アプリの起動より前に作成
    private let documents = DocumentController()
    private var defersWindow = false
    private lazy var settingsModel = SettingsModel(settings: .load()) { [weak self] settings in
        settings.save()
        self?.apply(settings)
    }

    /// didFinishLaunchingまで待つより、ウィンドウが約20ms速く表示される
    /// 起動したら、すべての下書きのウィンドウ、復元したウィンドウ、Finderから開いたファイルを開く
    func applicationWillFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        let settings = settingsModel.settings
        NSApp.mainMenu = MainMenu.make(autosavesInPlace: settings.fileAutosave == .inPlace)
        documents.apply(settings.fileAutosave)
        applyIconPlacement(settings.iconPlacement)
        // ログイン時に起動したかどうかは、didFinishLaunchingまでわからない
        defersWindow = LoginItem.mayLaunchAtLogin
        if !defersWindow {
            showDrafts()
        }
    }

    /// 下書きは起動したときに自身で開くので、AppKitには名称未設定の書類を開かせない
    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        false
    }

    /// ログイン時に起動したときは、ユーザーがPlainsongを開く操作をするまでウィンドウを開かない
    func applicationDidFinishLaunching(_: Notification) {
        guard defersWindow, !LoginItem.wasLaunchedAtLogin else { return }
        showDrafts()
    }

    /// 閉じた下書きはファイルに残っているので、本文のウィンドウがひとつも出ていなければ開き直す
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showEditors()
        return false
    }

    /// Sudden Terminationを有効にしているので、終了するときにはデリゲートが呼ばれない。下書きをまとめるのはここだけにする
    func applicationDidResignActive(_: Notification) {
        documents.saveChanges()
    }

    /// 起動を軽くするため、設定ウィンドウは開くまで作成しない
    @objc func showSettings(_: Any?) {
        let controller = settingsWindowController
            ?? SettingsWindowController(model: settingsModel, relaunch: { [weak self] in self?.relaunch() })
        settingsWindowController = controller
        // メニューバーのアイコンのメニューから開くときは、アプリをアクティブにする
        NSApp.activate()
        controller.showWindow(nil)
    }

    @objc func selectFontFamily(_ sender: NSMenuItem) {
        guard let fontFamily = sender.representedObject as? EditorSettings.FontFamily else { return }
        settingsModel.update { $0.fontFamily = fontFamily }
    }

    @objc func increaseFontSize(_: Any?) {
        guard let fontSize = fontSize(steppedBy: 1) else { return }
        settingsModel.update { $0.fontSize = fontSize }
    }

    @objc func decreaseFontSize(_: Any?) {
        guard let fontSize = fontSize(steppedBy: -1) else { return }
        settingsModel.update { $0.fontSize = fontSize }
    }

    @objc func selectFontSize(_ sender: NSMenuItem) {
        guard let fontSize = sender.representedObject as? CGFloat else { return }
        settingsModel.update { $0.fontSize = fontSize }
    }

    @objc func selectLineSpacing(_ sender: NSMenuItem) {
        guard let lineSpacing = sender.representedObject as? EditorSettings.LineSpacing else { return }
        settingsModel.update { $0.lineSpacing = lineSpacing }
    }

    @objc func toggleSetting(_ sender: NSMenuItem) {
        guard let keyPath = sender.representedObject as? WritableKeyPath<EditorSettings, Bool> else { return }
        settingsModel.update { $0[keyPath: keyPath].toggle() }
    }

    private func fontSize(steppedBy offset: Int) -> CGFloat? {
        let fontSizes = EditorSettings.fontSizes
        guard let index = fontSizes.firstIndex(of: settingsModel.settings.fontSize),
              fontSizes.indices.contains(index + offset) else { return nil }
        return fontSizes[index + offset]
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let settings = settingsModel.settings
        switch menuItem.action {
        case #selector(selectFontFamily(_:)):
            menuItem.state = menuItem.representedObject as? EditorSettings.FontFamily == settings.fontFamily
                ? .on
                : .off
        case #selector(increaseFontSize(_:)):
            return fontSize(steppedBy: 1) != nil
        case #selector(decreaseFontSize(_:)):
            return fontSize(steppedBy: -1) != nil
        case #selector(selectFontSize(_:)):
            menuItem.state = menuItem.representedObject as? CGFloat == settings.fontSize ? .on : .off
        case #selector(selectLineSpacing(_:)):
            menuItem.state = menuItem.representedObject as? EditorSettings.LineSpacing == settings.lineSpacing
                ? .on
                : .off
        case #selector(toggleSetting(_:)):
            guard let keyPath = menuItem.representedObject as? WritableKeyPath<EditorSettings, Bool> else { break }
            menuItem.state = settings[keyPath: keyPath] ? .on : .off
        default:
            break
        }
        return true
    }

    private func apply(_ settings: EditorSettings) {
        for editor in documents.editors {
            editor.apply(settings)
        }
        MainMenu.updateFileMenu(autosavesInPlace: settings.fileAutosave == .inPlace)
        documents.apply(settings.fileAutosave)
        applyIconPlacement(settings.iconPlacement)
    }

    private func relaunch() {
        documents.saveChanges()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    private func applyIconPlacement(_ placement: EditorSettings.IconPlacement) {
        let policy: NSApplication.ActivationPolicy = placement.showsInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            let isActive = NSApp.isActive
            NSApp.setActivationPolicy(policy)
            if isActive {
                NSApp.activate()
            }
        }
        if placement.showsInMenuBar, menuBarIcon == nil {
            menuBarIcon = MenuBarIcon { [weak self] in self?.showEditors() }
        } else if !placement.showsInMenuBar, let menuBarIcon {
            menuBarIcon.remove()
            self.menuBarIcon = nil
        }
    }

    private func showEditors() {
        if documents.hasVisibleEditors {
            NSApp.activate()
        } else {
            showDrafts()
        }
    }

    private func showDrafts() {
        NSApp.activate()
        documents.showDrafts()
    }
}
