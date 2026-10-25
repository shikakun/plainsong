import Foundation

/// 並び順とON/OFFはrawValueで保存するので、caseの名前を変えると設定が失われる
protocol ExtensionItemKind: RawRepresentable<String>, CaseIterable, Hashable where AllCases == [Self] {
    var title: String { get }
    var summary: String { get }
    var symbol: String? { get }
    var hasOptions: Bool { get }
}

extension ExtensionItemKind {
    var symbol: String? {
        nil
    }

    var hasOptions: Bool {
        false
    }
}

struct ExtensionItem<Kind: ExtensionItemKind>: Equatable {
    let kind: Kind
    var isEnabled: Bool

    static var defaults: [Self] {
        Kind.allCases.map { Self(kind: $0, isEnabled: false) }
    }

    static func load(from defaults: UserDefaults, orderKey: String, enabledKey: String) -> [Self] {
        func kinds(forKey key: String) -> [Kind] {
            (defaults.stringArray(forKey: key) ?? []).compactMap { Kind(rawValue: $0) }
        }
        let enabled = Set(kinds(forKey: enabledKey))
        return order(saved: kinds(forKey: orderKey)).map { Self(kind: $0, isEnabled: enabled.contains($0)) }
    }

    /// 並びを保存したあとに増えた項目は、`allCases`で1つ前にある項目のすぐ後ろに入れる
    static func order(saved: [Kind]) -> [Kind] {
        var order = saved
        var previous: Kind?
        for kind in Kind.allCases {
            if !order.contains(kind) {
                let index = previous.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                order.insert(kind, at: index)
            }
            previous = kind
        }
        return order
    }
}

enum ToolbarItemKind: String, ExtensionItemKind {
    case copy
    case find
    case save
    case share
    case delete

    var title: String {
        switch self {
        case .copy: String(localized: "toolbarItem.copy")
        case .find: String(localized: "toolbarItem.find")
        case .save: String(localized: "toolbarItem.save")
        case .share: String(localized: "toolbarItem.share")
        case .delete: String(localized: "toolbarItem.delete")
        }
    }

    var summary: String {
        switch self {
        case .copy: String(localized: "toolbarItem.copy.summary")
        case .find: String(localized: "toolbarItem.find.summary")
        case .save: String(localized: "toolbarItem.save.summary")
        case .share: String(localized: "toolbarItem.share.summary")
        case .delete: String(localized: "toolbarItem.delete.summary")
        }
    }

    var symbol: String? {
        switch self {
        case .copy: "doc.on.doc"
        case .find: "magnifyingglass"
        case .save: "square.and.arrow.down"
        case .share: "square.and.arrow.up"
        case .delete: "trash"
        }
    }

    var selectionOptionTitle: String? {
        switch self {
        case .copy: String(localized: "settings.toolbarItem.copy.usesSelection")
        case .find: String(localized: "settings.toolbarItem.find.usesSelection")
        case .save: nil
        case .share: String(localized: "settings.toolbarItem.share.usesSelection")
        case .delete: String(localized: "settings.toolbarItem.delete.usesSelection")
        }
    }

    var hasOptions: Bool {
        selectionOptionTitle != nil
    }
}

enum StatusBarItemKind: String, ExtensionItemKind {
    case characterCount
    case wordCount
    case fileEncoding
    case lineEnding

    var title: String {
        switch self {
        case .characterCount: String(localized: "statusBarItem.characterCount")
        case .wordCount: String(localized: "statusBarItem.wordCount")
        case .fileEncoding: String(localized: "statusBarItem.fileEncoding")
        case .lineEnding: String(localized: "statusBarItem.lineEnding")
        }
    }

    var summary: String {
        switch self {
        case .characterCount: String(localized: "statusBarItem.characterCount.summary")
        case .wordCount: String(localized: "statusBarItem.wordCount.summary")
        case .fileEncoding: String(localized: "statusBarItem.fileEncoding.summary")
        case .lineEnding: String(localized: "statusBarItem.lineEnding.summary")
        }
    }

    var hasOptions: Bool {
        switch self {
        case .characterCount, .wordCount: true
        case .fileEncoding, .lineEnding: false
        }
    }
}
