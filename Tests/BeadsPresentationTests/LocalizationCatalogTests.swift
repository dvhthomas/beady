import BeadsPresentation
import Foundation
import Testing

/// Every module's String Catalog ships complete: each string has every language Beady offers,
/// and each translation keeps the placeholders the code fills in. This is the check a
/// contributed translation has to pass (docs/LOCALIZATION.md), read from the repository so a
/// missing or broken entry fails here rather than showing an English fallback or crashing at
/// String(format:) time.
@Suite("String Catalogs")
struct LocalizationCatalogTests {
    static let modules = ["BeadsCore", "BeadsData", "BeadsPresentation", "Beady"]

    static var sourcesFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    static func catalog(_ module: String) throws -> [String: Any] {
        let url = sourcesFolder.appendingPathComponent("\(module)/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(json as? [String: Any], "\(module): not a JSON object")
    }

    /// Every language a catalog may carry; the source language is the key itself.
    static var languages: [String] { LanguageSetting.supported.filter { $0 != "en" } }

    /// The format placeholders in a string, in order, as the kind of value each takes:
    /// `%@`, `%lld`, `%d`… with any `%1$` position stripped, so a translation may reorder them.
    static func placeholders(_ text: String) -> [String] {
        let pattern = #"%(\d+\$)?([@a-zA-Z]+)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 2), in: text).map { String(text[$0]) }
        }.filter { $0 != "%" }
    }

    /// Every value a localization can resolve to: the plain unit, or each plural variant.
    static func values(in localization: [String: Any]) -> [String] {
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        if let variations = localization["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: Any] {
            return plural.values.compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
                .compactMap { $0["value"] as? String }
        }
        return []
    }

    @Test("the catalogs exist, are the source language's, and are not empty", arguments: modules)
    func shape(module: String) throws {
        let catalog = try Self.catalog(module)
        #expect(catalog["sourceLanguage"] as? String == "en")
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(!strings.isEmpty, "\(module) has no strings")
    }

    @Test("every string is translated into every language Beady offers", arguments: modules)
    func complete(module: String) throws {
        let strings = try #require(try Self.catalog(module)["strings"] as? [String: Any])
        for (key, entry) in strings {
            let entry = try #require(entry as? [String: Any], "\(module): \(key)")
            if entry["shouldTranslate"] as? Bool == false { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in Self.languages {
                let localization = localizations[language] as? [String: Any]
                #expect(localization != nil, "\(module): “\(key)” has no \(language)")
                guard let localization else { continue }
                let states = Self.states(in: localization)
                #expect(!states.isEmpty && states.allSatisfy { $0 == "translated" }, "\(module): “\(key)” in \(language) is \(states)")
                for value in Self.values(in: localization) {
                    #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(module): “\(key)” in \(language) is blank")
                }
            }
        }
    }

    @Test("a translation keeps the placeholders the code fills in", arguments: modules)
    func placeholdersAgree(module: String) throws {
        let strings = try #require(try Self.catalog(module)["strings"] as? [String: Any])
        for (key, entry) in strings {
            let entry = try #require(entry as? [String: Any])
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            // The key is the reference: the English entry, when there is one, only adds positions
            // or plural forms to it.
            let expected = Self.placeholders(key).sorted()
            let expectedOrder = Self.placeholders(key)
            for (language, localization) in localizations {
                guard let localization = localization as? [String: Any] else { continue }
                let isPlural = (localization["variations"] as? [String: Any]) != nil
                for value in Self.values(in: localization) {
                    let found = Self.placeholders(value).sorted()
                    // A plural form may spell its number out (“a bead”) and drop the %lld; it
                    // may not drop or invent anything else.
                    let agrees = found == expected
                        || (isPlural && found == expected.filter { $0 == "@" } && expected.contains("lld"))
                    #expect(agrees, "\(module): “\(key)” in \(language) has \(found), the source has \(expected): “\(value)”")
                    // A reordered placeholder needs a position, or the arguments land in the wrong slots.
                    if expected.count > 1, Self.placeholders(value) != expectedOrder {
                        #expect(value.contains("$"), "\(module): “\(key)” in \(language) reorders placeholders without %1$ positions: “\(value)”")
                    }
                }
            }
        }
    }

    @Test("the catalogs name no language Beady doesn't offer, so the picker and the files agree", arguments: modules)
    func onlyShippedLanguages(module: String) throws {
        let strings = try #require(try Self.catalog(module)["strings"] as? [String: Any])
        var seen: Set<String> = []
        for entry in strings.values {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            seen.formUnion(localizations.keys)
        }
        let unknown = seen.subtracting(LanguageSetting.supported)
        #expect(unknown.isEmpty, "\(module) carries \(unknown.sorted()); add them to LanguageSetting.supported or remove them")
    }

    static func states(in localization: [String: Any]) -> [String] {
        if let unit = localization["stringUnit"] as? [String: Any] {
            return [unit["state"] as? String ?? "?"]
        }
        if let variations = localization["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: Any] {
            return plural.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["state"] as? String }
        }
        return []
    }
}
