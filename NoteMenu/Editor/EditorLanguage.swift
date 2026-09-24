import Foundation

/// Uses the application's preferred language (including macOS per-app language settings).
/// Folder names and user-authored content are deliberately never translated.
enum EditorLanguage {
    static func text(_ chinese: String, _ english: String, languages: [String] = Locale.preferredLanguages) -> String {
        languages.first?.lowercased().hasPrefix("zh") == true ? chinese : english
    }
}
