import Foundation

enum AppIdentity {
    static let productName = "NotesMate"
    static let bundleIdentifier = "com.badpxx.notesmate"
}

/// Uses macOS's preferred language, including the per-app override, unless a Debug
/// language is selected. User content and folder names are never translated.
enum EditorLanguage {
    static let supported = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "de", "fr", "es", "pt", "it", "fil", "id", "ms", "th", "vi"]
    static let didChangeNotification = Notification.Name("NotesMate.editorLanguageDidChange")

    #if DEBUG
    private static let debugOverrideKey = "NotesMate.debug.languageOverride"
    static var debugOverride: String? {
        guard let value = UserDefaults.standard.string(forKey: debugOverrideKey), supported.contains(value) else { return nil }
        return value
    }

    static func setDebugOverride(_ language: String?) {
        let value = language.flatMap { supported.contains($0) ? $0 : nil }
        if let value {
            UserDefaults.standard.set(value, forKey: debugOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: debugOverrideKey)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
    #endif

    private static var preferredLanguages: [String] {
        #if DEBUG
        if let debugOverride { return [debugOverride] }
        #endif
        return Locale.preferredLanguages
    }
    static func language(for languages: [String]) -> String {
        guard let first = languages.first else { return "en" }
        let parts = first.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        guard let base = parts.first else { return "en" }
        if base == "zh" {
            if parts.contains("hant") { return "zh-Hant" }
            if parts.contains("hans") { return "zh-Hans" }
            return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
        }
        if base == "tl" { return "fil" }
        if base == "in" { return "id" }
        return supported.contains(base) ? base : "en"
    }

    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
    // Immutable catalogs are safe to read from the background Notes-saving queue.
    private static let catalogs: [String: [String: String]] = Dictionary(uniqueKeysWithValues: supported.map { language in
        // SwiftPM lowercases localization directory names; Xcode preserves script casing.
        guard let directory = resources.url(forResource: language, withExtension: "lproj")
                ?? resources.url(forResource: language.lowercased(), withExtension: "lproj"),
              let data = try? Data(contentsOf: directory.appendingPathComponent("Localizable.strings")),
              let table = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            return (language, [:])
        }
        return (language, table)
    })

    static func text(_ key: String, languages: [String]? = nil) -> String {
        catalogs[language(for: languages ?? preferredLanguages)]?[key] ?? catalogs["en"]?[key] ?? key
    }

    /// Single-pass substitution keeps inserted filenames/errors literal, even if they
    /// contain tokens or percent signs. Translations may reorder numbered arguments.
    static func format(_ key: String, _ values: String..., languages: [String]? = nil) -> String {
        let message = text(key, languages: languages)
        let result = NSMutableString(string: message)
        let regex = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
        for match in regex.matches(in: message, range: NSRange(location: 0, length: (message as NSString).length)).reversed() {
            let index = Int((message as NSString).substring(with: match.range(at: 1)))!
            if values.indices.contains(index) { result.replaceCharacters(in: match.range, with: values[index]) }
        }
        return result as String
    }
    static func catalog(for language: String) -> [String: String] { catalogs[language] ?? [:] }
}
