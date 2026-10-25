import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// The switcher at the top of the sidebar: recents in Open Recent's order, each with its path
/// and bd prefix, ⌃⌘O round the list, and the prefix read off a database's ids.
@Suite("Workspace switcher")
struct WorkspaceSwitchingTests {
    @Test("recents keep Open Recent's order and carry the prefix remembered for each path")
    func recents() {
        let recents = WorkspaceSwitching.recents(paths: ["/a/beady", "/b/tiles", "/c/beady"], prefixes: ["/a/beady": "bdv", "/c/beady": "bdv"])
        #expect(recents.map(\.name) == ["beady", "tiles", "beady"])
        #expect(recents.map(\.prefix) == ["bdv", nil, "bdv"])
        #expect(recents.map(\.id) == ["/a/beady", "/b/tiles", "/c/beady"], "two checkouts of one project differ by path")
    }

    @Test("next goes round the recents and stops offering when there is nowhere else to go")
    func next() {
        let paths = ["/a", "/b", "/c"]
        #expect(WorkspaceSwitching.next(after: "/a", in: paths) == "/b")
        #expect(WorkspaceSwitching.next(after: "/c", in: paths) == "/a", "round again")
        #expect(WorkspaceSwitching.next(after: "/zzz", in: paths) == "/a", "a current workspace not in the list starts at the top")
        #expect(WorkspaceSwitching.next(after: nil, in: paths) == "/a")
        #expect(WorkspaceSwitching.next(after: "/a", in: ["/a"]) == nil)
        #expect(WorkspaceSwitching.next(after: nil, in: []) == nil)
    }

    @Test("the prefix is what every id shares up to a dash, and the common first segment otherwise")
    func prefix() {
        #expect(WorkspaceSwitching.prefix(of: ["bdv-jlx.10", "bdv-2ka", "bdv-qbe"]) == "bdv")
        #expect(WorkspaceSwitching.prefix(of: ["my-app-1", "my-app-2x"]) == "my-app", "a prefix may carry a dash of its own")
        #expect(WorkspaceSwitching.prefix(of: ["bdv-1"]) == "bdv")
        #expect(WorkspaceSwitching.prefix(of: ["bdv-1", "bdv-2", "other-3"]) == "bdv", "an imported stray doesn't hide the prefix")
        #expect(WorkspaceSwitching.prefix(of: []) == nil)
        #expect(WorkspaceSwitching.prefix(of: ["beady-1a2", "beady-1a3"]) == "beady")
    }

    @Test("⌃⌘O is written the way macOS writes it, and counts as a ⌘ key")
    func controlKey() {
        let binding = KeyBinding("o", [.control, .command])
        #expect(binding.display == "⌃⌘O")
        #expect(!binding.isPlainKey)
        #expect(AppCommand.nextWorkspace.bindings == [binding])
    }

    @Test("a switch command is named after the workspace and answers to its name and path")
    func commands() {
        let command = AppCommand.switchWorkspace(path: "/Users/ann/code/tiles")
        #expect(command.title == "Switch to tiles")
        #expect(command.id == "switch-/Users/ann/code/tiles")
        #expect(command.keywords.contains("tiles") && command.keywords.contains("/Users/ann/code/tiles"))
        #expect(command.group == AppCommand.openWorkspace.group)
    }
}
