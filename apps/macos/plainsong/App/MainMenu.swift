import AppKit

enum MainMenu {
    static func make(autosavesInPlace: Bool) -> NSMenu {
        let windowMenu = menu("menu.window", [
            item("menu.minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"),
            item("menu.zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("menu.bringAllToFront", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = windowMenu

        let mainMenu = NSMenu()
        let fileMenu = fileMenu()
        for submenu in [appMenu(), fileMenu, editMenu(), viewMenu(), windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        updateFileMenu(fileMenu, autosavesInPlace: autosavesInPlace)
        return mainMenu
    }

    static func updateFileMenu(autosavesInPlace: Bool) {
        guard let fileMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: {
            $0.items.contains { $0.action == #selector(NSDocument.saveAs(_:)) }
        }) else { return }
        updateFileMenu(fileMenu, autosavesInPlace: autosavesInPlace)
    }

    /// 「複製」を隠すときは、ショートカットも外す。隠した項目に同じショートカットが残っていると、「名前を付けて保存…」の⇧⌘Sが効かなくなる
    private static func updateFileMenu(_ menu: NSMenu, autosavesInPlace: Bool) {
        for item in menu.items {
            switch item.action {
            case #selector(NSDocument.duplicate(_:)):
                item.isHidden = !autosavesInPlace
                item.keyEquivalent = autosavesInPlace ? "s" : ""
            case #selector(NSDocument.rename(_:)), #selector(NSDocument.move(_:)):
                item.isHidden = !autosavesInPlace
            case #selector(NSDocument.saveAs(_:)):
                item.isAlternate = autosavesInPlace
                item.keyEquivalentModifierMask = autosavesInPlace ? [.command, .shift, .option] : [.command, .shift]
            default:
                break
            }
        }
    }

    private static func appMenu() -> NSMenu {
        // アプリメニューのタイトルはシステムがアプリ名に置き換える
        menu(nil, [
            item("menu.about", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            settingsItem(),
            .separator(),
            item("menu.hide", #selector(NSApplication.hide(_:)), key: "h"),
            item(
                "menu.hideOthers",
                #selector(NSApplication.hideOtherApplications(_:)),
                key: "h",
                modifiers: [.command, .option]
            ),
            item("menu.showAll", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("menu.quit", #selector(NSApplication.terminate(_:)), key: "q"),
        ])
    }

    /// 「最近使った項目を開く」は、NSDocumentControllerが「開く…」の下に自動で加える
    private static func fileMenu() -> NSMenu {
        menu("menu.file", [
            item("menu.newWindow", #selector(NSDocumentController.newDocument(_:)), key: "n"),
            item("menu.open", #selector(NSDocumentController.openDocument(_:)), key: "o"),
            .separator(),
            item("menu.close", #selector(NSWindow.performClose(_:)), key: "w"),
            item("menu.save", #selector(NSDocument.save(_:)), key: "s"),
            item("menu.duplicate", #selector(NSDocument.duplicate(_:)), modifiers: [.command, .shift]),
            item("menu.saveAs", #selector(NSDocument.saveAs(_:)), key: "s"),
            item("menu.rename", #selector(NSDocument.rename(_:))),
            item("menu.moveTo", #selector(NSDocument.move(_:))),
        ])
    }

    private static func editMenu() -> NSMenu {
        menu("menu.edit", [
            // undo:とredo:はSDKに宣言がなく、#selectorでは参照できない
            item("menu.undo", Selector(("undo:")), key: "z"),
            item("menu.redo", Selector(("redo:")), key: "Z"),
            .separator(),
            item("menu.cut", #selector(NSText.cut(_:)), key: "x"),
            item("menu.copy", #selector(NSText.copy(_:)), key: "c"),
            item("menu.paste", #selector(NSText.paste(_:)), key: "v"),
            item("menu.selectAll", #selector(NSText.selectAll(_:)), key: "a"),
        ])
    }

    private static func viewMenu() -> NSMenu {
        let fontFamilies = EditorSettings.FontFamily.allCases.map { fontFamily in
            choice(fontFamily.title, #selector(AppDelegate.selectFontFamily(_:)), fontFamily)
        }
        let fontSizes = EditorSettings.fontSizes.map { fontSize in
            choice(
                String(localized: "settings.fontSize.value \(Int(fontSize))"),
                #selector(AppDelegate.selectFontSize(_:)),
                fontSize
            )
        }
        let lineSpacings = EditorSettings.LineSpacing.allCases.map { lineSpacing in
            choice(lineSpacing.title, #selector(AppDelegate.selectLineSpacing(_:)), lineSpacing)
        }
        return menu("menu.view", [
            submenu("settings.fontSize", [
                item("menu.fontSize.bigger", #selector(AppDelegate.increaseFontSize(_:)), key: "+"),
                item("menu.fontSize.smaller", #selector(AppDelegate.decreaseFontSize(_:)), key: "-"),
                .separator(),
            ] + fontSizes),
            submenu("settings.lineSpacing", lineSpacings),
            submenu("settings.fontFamily", fontFamilies),
            .separator(),
            toggle("settings.kerning", \.usesKerning, key: "k"),
            toggle("settings.showsNewlines", \.showsNewlines, key: "l"),
            toggle("settings.showsWhitespace", \.showsWhitespace, key: "i"),
            toggle("settings.showsLineNumbers", \.showsLineNumbers, key: "n"),
            toggle("settings.usesReadableWidth", \.usesReadableWidth, key: "r"),
            .separator(),
            item(
                "menu.enterFullScreen",
                #selector(NSWindow.toggleFullScreen(_:)),
                key: "f",
                modifiers: [.control, .command]
            ),
        ])
    }

    private static func submenu(_ title: String.LocalizationValue, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: title), action: nil, keyEquivalent: "")
        item.submenu = menu(title, items)
        return item
    }

    private static func choice(_ title: String, _ action: Selector, _ value: Any) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = value
        return item
    }

    private static func toggle(
        _ title: String.LocalizationValue,
        _ keyPath: WritableKeyPath<EditorSettings, Bool>,
        key: String
    ) -> NSMenuItem {
        let item = item(title, #selector(AppDelegate.toggleSetting(_:)), key: key, modifiers: [.command, .option])
        item.representedObject = keyPath
        return item
    }

    private static func menu(_ title: String.LocalizationValue?, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title.map { String(localized: $0) } ?? "")
        menu.items = items
        return menu
    }

    static func settingsItem() -> NSMenuItem {
        let item = item("menu.settings", #selector(AppDelegate.showSettings(_:)), key: ",")
        item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        return item
    }

    static func item(
        _ title: String.LocalizationValue,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
