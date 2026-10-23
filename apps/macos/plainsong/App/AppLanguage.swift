import Foundation

/// 表示言語
enum AppLanguage: CaseIterable {
    case system
    case english
    case japanese

    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: bundleIdentifier)?[key] as? [String],
              let language = languages.first
        else { return .system }
        let languageCode = Locale.Language(identifier: language).languageCode?.identifier
        return allCases.first { $0.identifier == languageCode } ?? .system
    }

    var title: String {
        switch self {
        case .system: String(localized: "settings.language.system")
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    private var identifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .japanese: "ja"
        }
    }

    /// AppleLanguagesは起動するときにしか読まれないので、今の表示言語と違う言語は起動し直すまで反映されない
    var requiresRelaunch: Bool {
        let systemLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[Self.key]
        let localization = identifier ?? Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: systemLanguages as? [String]
        ).first
        return localization != Bundle.main.preferredLocalizations.first
    }

    func select() {
        if let identifier {
            UserDefaults.standard.set([identifier], forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
