import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// Reset Configuration removes everything Beady keeps per user, and nothing it wrote into a
/// workspace. The inventory is the one list of what that is.
@Suite("Reset Configuration")
struct ConfigurationResetTests {
    /// Every preferences key written anywhere under Sources, found by reading the code, so a new
    /// key can't be written without being listed, and a listed key can't quietly stop existing.
    @Test("the inventory names every preferences key Beady writes, and nothing stale")
    func knownKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let patterns = [#"forKey: "([^"]+)""#, #"AppStorage\("([^"]+)"\)"#, #"[kK]ey = "([^"]+)""#]
        var written: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let range = Range(match.range(at: 1), in: text) { written.insert(String(text[range])) }
                }
            }
        }
        #expect(written.count > 10, "the scan should find the keys the app writes")
        let unlisted = written.subtracting(ConfigurationInventory.allKnownKeys)
        #expect(unlisted.isEmpty, "written but not in the inventory: \(unlisted.sorted())")
        let stale = ConfigurationInventory.allKnownKeys.subtracting(written)
        #expect(stale.isEmpty, "in the inventory but no longer written: \(stale.sorted())")
    }

    @Test("the inventory says what is there, with counts, and counts the Library's views")
    func lines() {
        let inventory = ConfigurationInventory(
            presentKeys: ["recentWorkspaces", "views", "liveViews", "appearance", "textSize", "issueListColumns", "eventsJournalTurnedOn", "NSNavPanelExpandedSizeForOpenMode"],
            recentWorkspaces: 3, journalWorkspaces: 2, libraryViews: 4
        )
        #expect(inventory.lines.map(\.title) == ["Remembered workspaces", "Views", "Saved views in the Library", "Appearance", "Window layout", "Change journal", "Other settings"])
        #expect(inventory.lines.map(\.detail) == ["3", "filters, layouts and which view was open", "4", "theme, text size and sidebar style", "columns and the details pane width", "the setting, and 2 workspaces it was turned on in", "1"])
        #expect(inventory.libraryViews == 4)
        #expect(!inventory.isEmpty)

        let bare = ConfigurationInventory(presentKeys: [], recentWorkspaces: 0, journalWorkspaces: 0, libraryViews: 0)
        #expect(bare.lines.map(\.title) == ["Saved views in the Library"])
        #expect(bare.lines.first?.detail == "none")
        #expect(bare.isEmpty)
        let one = ConfigurationInventory(presentKeys: ["eventsJournalTurnedOn"], recentWorkspaces: 0, journalWorkspaces: 1, libraryViews: 0)
        #expect(one.lines.last?.detail == "the setting, and 1 workspace it was turned on in")
        // The language is macOS's own per-app key, and a reset puts it back to the system's.
        let language = ConfigurationInventory(presentKeys: ["AppleLanguages"], recentWorkspaces: 0, journalWorkspaces: 0, libraryViews: 0)
        #expect(language.lines.map(\.title) == ["Saved views in the Library", "Language"])
        #expect(language.lines.last?.detail == "back to the system language")
    }

    @Test("the plan removes the Library only when asked, and the commands say exactly that")
    func plan() {
        let inventory = ConfigurationInventory(presentKeys: ["views"], recentWorkspaces: 0, journalWorkspaces: 0, libraryViews: 2)
        #expect(inventory.plan(deletingLibrary: false) == ResetPlan(removesPreferences: true, removesLibrary: false))
        #expect(inventory.plan(deletingLibrary: true) == ResetPlan(removesPreferences: true, removesLibrary: true))
        #expect(inventory.commands(deletingLibrary: false) == ["defaults delete me.bitsby.beady"])
        #expect(inventory.commands(deletingLibrary: true) == ["defaults delete me.bitsby.beady", "rm -rf ~/Library/Application\\ Support/Beady"])
        #expect(ConfigurationInventory.leavesAlone.contains("workspace"))
    }

    @Test("performing a reset clears every key, leaves the Library unless asked, and removes it when asked")
    func perform() throws {
        let name = "beady-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("beady-reset-\(UUID().uuidString)", isDirectory: true)
        let views = folder.appendingPathComponent("views", isDirectory: true)
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: views.appendingPathComponent("x.beadyview"))
        func seed() {
            defaults.set(["/a", "/b"], forKey: "recentWorkspaces")
            defaults.set("dark", forKey: "appearance")
            defaults.set(360, forKey: "inspectorWidth")
        }

        seed()
        try ConfigurationReset.perform(ResetPlan(removesPreferences: true, removesLibrary: false), defaults: defaults, domain: name, libraryFolder: folder)
        #expect(defaults.object(forKey: "recentWorkspaces") == nil)
        #expect(defaults.object(forKey: "appearance") == nil)
        #expect(defaults.object(forKey: "inspectorWidth") == nil)
        #expect((defaults.persistentDomain(forName: name) ?? [:]).isEmpty)
        #expect(FileManager.default.fileExists(atPath: views.appendingPathComponent("x.beadyview").path), "the Library stays unless asked")

        seed()
        try ConfigurationReset.perform(ResetPlan(removesPreferences: true, removesLibrary: true), defaults: defaults, domain: name, libraryFolder: folder)
        #expect(defaults.object(forKey: "recentWorkspaces") == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path), "and goes when asked")

        // A Library that was never created is not an error.
        try ConfigurationReset.perform(ResetPlan(removesPreferences: true, removesLibrary: true), defaults: defaults, domain: name, libraryFolder: folder)
    }
}
