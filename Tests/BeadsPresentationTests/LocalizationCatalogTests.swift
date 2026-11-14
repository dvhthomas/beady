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

    /// The build has to compile the catalogs, not copy them: only SwiftPM's Swift Build backend
    /// does (scripts/swift-flags.sh passes --build-system swiftbuild where the toolchain has it).
    /// Without this, the app comes up in English with no plural forms and nothing else says why.
    @Test("the build compiled the catalogs into the bundle; see scripts/swift-flags.sh if not")
    func compiled() {
        for language in Self.languages {
            #expect(LanguageSetting.hasCompiledCatalog(for: language), "no compiled \(language) catalog in the BeadsPresentation bundle: this toolchain's build system copied Localizable.xcstrings instead of compiling it. Use Swift 6.4+, or pass --build-system swiftbuild (scripts/test.sh and scripts/bundle.sh do).")
        }
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

    /// The calls whose first string literal is a catalog key. Every module uses
    /// `String(localized:)`; only the app has SwiftUI's own, which take a `LocalizedStringKey`.
    static func localizingCalls(in module: String) -> [String] {
        let everywhere = [#"String\(localized:\s*"#]
        guard module == "Beady" else { return everywhere }
        return everywhere + [
            #"\bText\("#, #"\bButton\("#, #"\bLabel\("#, #"\.help\("#, #"\bToggle\("#, #"\bSection\("#,
            #"\bPicker\("#, #"\bMenu\("#, #"\bTextField\("#, #"\.navigationTitle\("#, #"\bLabeledContent\("#,
            #"\bContentUnavailableView\("#, #"\bProgressView\("#, #"\.alert\("#, #"\bDisclosureGroup\("#,
            #"\.accessibilityLabel\("#,
        ]
    }

    /// Reads the Swift string literal whose opening quote is at `start`, with each `\(…)`
    /// interpolation written as a bare `%` — the compiler makes it `%@` or `%lld` by the value's
    /// type, which a reader of the source can't know. Nil for a literal that runs off its line.
    static func literal(in source: [Character], from start: Int) -> (text: String, end: Int)? {
        var text = ""
        var index = start + 1
        while index < source.count {
            let character = source[index]
            if character == "\"" { return (text, index) }
            if character == "\n" { return nil }
            guard character == "\\", index + 1 < source.count else {
                text.append(character)
                index += 1
                continue
            }
            let escaped = source[index + 1]
            guard escaped == "(" else {
                text.append(escaped == "n" ? "\n" : escaped == "t" ? "\t" : escaped)
                index += 2
                continue
            }
            // An interpolation: skip to its closing parenthesis, stepping over any literal inside.
            var depth = 1
            index += 2
            while index < source.count, depth > 0 {
                switch source[index] {
                case "(": depth += 1
                case ")": depth -= 1
                case "\"":
                    guard let nested = literal(in: source, from: index) else { return nil }
                    index = nested.end
                default: break
                }
                index += 1
            }
            text.append("%")
        }
        return nil
    }

    /// A catalog key with its placeholders reduced to the same bare `%` as `literal` leaves.
    static func withoutPlaceholderTypes(_ key: String) -> String {
        key.replacingOccurrences(of: #"%(\d+\$)?(lld|ld|d|@|lf|f|s)"#, with: "%", options: .regularExpression)
    }

    /// A string the code shows that no catalog carries appears in English in every language, and
    /// the completeness check above can't see it: it only reads keys a catalog already has.
    @Test("every string the code shows is in its module's catalog", arguments: modules)
    func nothingLeftOut(module: String) throws {
        let strings = try #require(try Self.catalog(module)["strings"] as? [String: Any])
        let known = Set(strings.keys.map(Self.withoutPlaceholderTypes))
        let folder = Self.sourcesFolder.appendingPathComponent(module)
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "\(module): no Swift files under \(folder.path)")
        let calls = try Self.localizingCalls(in: module).map { try NSRegularExpression(pattern: $0 + "\"") }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let source = Array(text)
            for call in calls {
                for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range, in: text) else { continue }
                    let quote = text.distance(from: text.startIndex, to: range.upperBound) - 1
                    // A multi-line literal opens with three quotes; none of ours is a key.
                    if quote + 2 < source.count, source[quote + 1] == "\"", source[quote + 2] == "\"" { continue }
                    guard let literal = Self.literal(in: source, from: quote) else { continue }
                    // Nothing but a value ("\(count)") is not a string to translate.
                    if literal.text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")).isEmpty { continue }
                    #expect(
                        known.contains(literal.text),
                        "\(module): “\(literal.text)” in \(file.lastPathComponent) is not in the catalog. Run scripts/sync-strings.sh and translate it (docs/LOCALIZATION.md); for text that must not be translated, use Text(verbatim:)."
                    )
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
