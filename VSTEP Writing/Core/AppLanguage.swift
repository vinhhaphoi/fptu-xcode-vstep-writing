import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return String(localized: "language_english")
        case .vietnamese: return String(localized: "language_vietnamese")
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .vietnamese: return "🇻🇳"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

// Dung @Observable thay ObservableObject de tuong thich Swift 6
@Observable
@MainActor
class LanguageManager {
    // AppStorage luu vao UserDefaults, persist khi restart app
    @ObservationIgnored
    @AppStorage("app_language") private var _selectedLanguage: String = AppLanguage.english.rawValue

    var selectedLanguage: String {
        get {
            access(keyPath: \.selectedLanguage)
            return _selectedLanguage
        }
        set {
            withMutation(keyPath: \.selectedLanguage) {
                _selectedLanguage = newValue
            }
        }
    }

    var currentLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguage) ?? .english
    }

    func setLanguage(_ language: AppLanguage) {
        selectedLanguage = language.rawValue
    }
}
