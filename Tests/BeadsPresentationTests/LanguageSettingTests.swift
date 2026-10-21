import BeadsPresentation
import Foundation
import Testing

/// The language setting is macOS's own per-app language, read and written under its key.
@Suite("Language setting")
struct LanguageSettingTests {
    @Test("the key is the one System Settings writes, and the choices start with the system's")
    func key() {
        #expect(LanguageSetting.key == "AppleLanguages")
        #expect(LanguageSetting.choices.first == .some(nil))
        #expect(LanguageSetting.choices.dropFirst().compactMap { $0 } == LanguageSetting.supported)
        #expect(LanguageSetting.supported.first == "en", "the source language leads")
    }

    @Test("what is stored is read back, dialects land on the shipped language, and anything else is the system default")
    func chosen() {
        #expect(LanguageSetting.chosen(from: nil) == nil)
        #expect(LanguageSetting.chosen(from: ["de"]) == "de")
        #expect(LanguageSetting.chosen(from: ["pt-BR"]) == "pt-BR")
        #expect(LanguageSetting.chosen(from: ["de-AT", "en"]) == "de", "Austrian German is still German")
        #expect(LanguageSetting.chosen(from: ["pt-PT"]) == "pt-BR", "the one Portuguese shipped")
        #expect(LanguageSetting.chosen(from: ["it"]) == nil, "a language without a catalog follows the system")
        #expect(LanguageSetting.chosen(from: []) == nil)
        #expect(LanguageSetting.chosen(from: "de") == nil, "not the array macOS expects")
    }

    @Test("a choice is stored as the one-element list macOS expects; the system default removes the key")
    func stored() {
        #expect(LanguageSetting.stored(for: "ja") == ["ja"])
        #expect(LanguageSetting.stored(for: nil) == nil)
        for code in LanguageSetting.supported {
            #expect(LanguageSetting.chosen(from: LanguageSetting.stored(for: code)) == code)
        }
    }

    @Test("languages are named in themselves, then in the current language when that differs")
    func names() {
        let english = Locale(identifier: "en")
        #expect(LanguageSetting.displayName("de", in: english) == "Deutsch — German")
        #expect(LanguageSetting.displayName("en", in: english) == "English")
        #expect(LanguageSetting.displayName("fr", in: english) == "Français — French", "Foundation's lower-case name is capitalised")
        #expect(LanguageSetting.displayName("ja", in: english) == "日本語 — Japanese")
        #expect(LanguageSetting.displayName("pt-BR", in: english) == "Português (Brasil) — Portuguese (Brazil)")
        #expect(LanguageSetting.displayName("de", in: Locale(identifier: "de")) == "Deutsch")
        #expect(LanguageSetting.title(for: nil, in: english) == "System Default")
        #expect(LanguageSetting.title(for: "ko", in: english) == "한국어 — Korean")
    }
}
