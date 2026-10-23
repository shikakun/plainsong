import AppKit

final class MenuBarIcon: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init()
        menu.items = [
            MainMenu.settingsItem(),
            .separator(),
            MainMenu.item("menu.quit", #selector(NSApplication.terminate(_:)), key: "q"),
        ]
        menu.delegate = self
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.setAccessibilityLabel("Plainsong")
        button.target = self
        button.action = #selector(click(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// メニューを付けたままにすると左クリックでもメニューが出るので、出すときだけ付ける
    @objc private func click(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            sender.performClick(nil)
        } else {
            onClick()
        }
    }

    func menuDidClose(_: NSMenu) {
        statusItem.menu = nil
    }
}
