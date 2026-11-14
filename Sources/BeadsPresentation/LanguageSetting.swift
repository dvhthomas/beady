import Foundation

/// The language Beady is shown in: the system's, or one chosen for Beady alone.
///
/// macOS already has a per-app language. System Settings › General › Language & Region ›
/// Applications writes an `AppleLanguages` array into the app's own preferences, and every
/// bundle lookup follows it from the next launch. Beady's setting writes that same key, so the
/// two can't disagree, and System Default simply means the key isn't there. Nothing is looked
/// up differently at runtime: the catalogs in each module do what they always do.
public enum LanguageSetting {
    /// The preferences key macOS reads; it lives in Beady's own domain, never the global one.
    public static let key = "AppleLanguages"

    /// The languages Beady ships catalogs for, in the order the picker lists them: the source
    /// language first, then the rest by their English names. A new translation is added here
    /// and in each module's Localizable.xcstrings (docs/LOCALIZATION.md).
    public static let supported: [String] = ["en", "de", "es", "fr", "ja", "ko", "pt-BR"]

    /// What the picker and the palette offer: the system's language, then each shipped one.
    public static var choices: [String?] { [nil] + supported.map { $0 } }

    /// The chosen language, given what is stored under `key` in Beady's own domain (not
    /// `UserDefaults.standard`, which would answer with the system's list). Nil is the system
    /// default; so is a value Beady can't honour. A stored dialect lands on the shipped language
    /// it belongs to, so `de-AT` chooses German.
    public static func chosen(from stored: Any?) -> String? {
        guard let list = stored as? [String], let first = list.first, !first.isEmpty else { return nil }
        if supported.contains(first) { return first }
        let language = Locale(identifier: first).language.languageCode?.identifier
        return supported.first { Locale(identifier: $0).language.languageCode?.identifier == language }
    }

    /// What to store for a choice: the one-element list macOS expects, or nil to remove the key
    /// and follow the system again.
    public static func stored(for choice: String?) -> [String]? {
        choice.map { [$0] }
    }

    /// A language named the way System Settings names it: in itself, then in the current
    /// language when that differs, as in “Deutsch — German”.
    public static func displayName(_ code: String, in locale: Locale = .current) -> String {
        let own = Locale(identifier: code)
        let native = capitalized(own.localizedString(forIdentifier: code) ?? code, in: own)
        let current = capitalized(locale.localizedString(forIdentifier: code) ?? code, in: locale)
        return native == current ? native : String(localized: "\(native) — \(current)", bundle: .module, comment: "A language named in itself, then in the current language: “Deutsch — German”")
    }

    /// Whether the build compiled the catalog for a language into this module's bundle. Only
    /// SwiftPM's Swift Build backend does (scripts/swift-flags.sh); an older build system copies
    /// the .xcstrings file untouched, which Foundation can't read, and the app would come up in
    /// English with no plural forms. A test holds every build to this.
    public static func hasCompiledCatalog(for code: String) -> Bool {
        Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: code) != nil
    }

    /// The picker's label for a choice: the language's name, or System Default.
    public static func title(for choice: String?, in locale: Locale = .current) -> String {
        guard let choice else { return String(localized: "System Default", bundle: .module, comment: "Language choice: follow macOS") }
        return displayName(choice, in: locale)
    }

    /// Foundation names some languages in lower case (“français”); a list entry starts upper.
    private static func capitalized(_ name: String, in locale: Locale) -> String {
        guard let first = name.first else { return name }
        return String(first).uppercased(with: locale) + name.dropFirst()
    }
}
