import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case chinese = "zh-Hans"
    case english = "en"
    case french = "fr"
    case portuguese = "pt"
    case spanish = "es"

    private static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        get {
            guard let value = UserDefaults.standard.string(forKey: defaultsKey),
                  let language = AppLanguage(rawValue: value) else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var title: String {
        switch self {
        case .system: L10n.text("language.system")
        case .chinese: L10n.text("language.chinese")
        case .english: L10n.text("language.english")
        case .french: L10n.text("language.french")
        case .portuguese: L10n.text("language.portuguese")
        case .spanish: L10n.text("language.spanish")
        }
    }
}

enum L10n {
    private static var localizedBundle: Bundle {
        let language = AppLanguage.current
        guard language != .system,
              let path = Bundle.main.path(
                forResource: language.rawValue,
                ofType: "lproj"
              ),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: localizedBundle,
            value: key,
            comment: ""
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
